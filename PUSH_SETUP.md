# Push Notifications Setup (Live Chat – Admin Alerts)

This doc covers what’s implemented and what you need to configure so admins get push when the app is closed or in the background.

## Implemented

- **Firestore**
  - `support_threads/{threadId}` with `userId`, `updatedAt`
  - `support_threads/{threadId}/messages/{messageId}` with `senderUid`, `senderRole`, `text`, `createdAt`
  - User FCM fields: `users/{uid}` → `fcmToken`, `platform`, `tokenUpdatedAt`

- **Flutter**
  - Notification permission request on start/login
  - FCM token stored in Firestore on init and on token refresh
  - Admins subscribed to topic `admins`
  - Background handler so notifications can be received when app is terminated

- **Cloud Function**
  - `onSupportMessageCreated`: triggers on `support_threads/{threadId}/messages/{messageId}` onCreate
  - If `senderRole === 'user'`: send to topic `admins` (title: “New support message”, body: preview, data: `threadId`)
  - If `senderRole === 'admin'`: send to user’s `fcmToken` (title: “Support reply”, body: preview)

## iOS Checklist

1. **APNs Auth Key**
   - In [Apple Developer](https://developer.apple.com/account/resources/authkeys/list): create an APNs key (.p8), download it once, note Key ID and Team ID.
   - In [Firebase Console](https://console.firebase.google.com) → Project → Project settings → Cloud Messaging:
     - Under **Apple app configuration**, upload the APNs Auth Key (.p8) and enter Key ID, Team ID, and Bundle ID.

2. **Xcode capabilities**
   - **Push Notifications**: enabled.
   - **Background Modes**: **Remote notifications** enabled.  
   - (Already set in this project: `UIBackgroundModes` includes `remote-notification` in `Info.plist`.)

3. **Payload**
   - The Cloud Function sends both `notification` and `data`. With `content-available: 1` in `aps`, the system can wake the app so the notification is shown even when the app is terminated.

4. **Testing**
   - Use a real device (push does not work in the iOS Simulator).
   - Build with a proper signing team and run on device. Send a message from a user account; an admin device (with the app closed or in background) should get “New support message” and see the notification.

## Android

- No extra project setup beyond the existing Firebase/Google config.
- The function uses FCM with `priority: 'high'` so notifications are delivered when the app is in the background or closed.

## Dependencies

The app uses `firebase_messaging`. If `flutter pub get` fails with a version conflict, run:

```bash
flutter pub add firebase_messaging
```

If that still conflicts with `firebase_core`/`firebase_storage`, try upgrading FlutterFire packages together (e.g. `flutter pub upgrade` or adjust versions in `pubspec.yaml` so all firebase_* packages are compatible).

## Deploy

```bash
# Firestore rules + indexes
firebase deploy --only firestore

# Cloud Functions (includes onSupportMessageCreated)
firebase deploy --only functions
```

## Verify

1. Log in as **admin** on a device, allow notifications → token is saved and device is subscribed to `admins`.
2. Log in as **user** on another device (or web), open Live Chat, send a message.
3. Admin device (app closed or in background) should show “New support message” with the message preview and receive it even when the app was terminated.

## Firestore rules

After changing `firestore.rules`, deploy with:

```bash
firebase deploy --only firestore:rules
```

If you changed `firestore.indexes.json`, also run:

```bash
firebase deploy --only firestore:indexes
```

## Deposit withdraw & delivery timeout

- **requestDepositWithdraw** (callable): Users can withdraw available deposit. Server checks `reservedDeposit === 0` and `depositStatus !== 'in_dispute'`, then refunds via Stripe using stored `depositRefs` and updates wallet (backend-only fields).
- **deliveryConfirmationTimeout** (scheduled, daily 09:00 UTC): Sets `deliveryStatus = 'needs_admin_review'` for ENDED auctions where delivery is still pending after 7 days (or `adminSettings/fees.deliveryConfirmationTimeoutDays`), and sends a push to admins. No auto-release; admin must resolve.
- Wallet deposit refs: On `payment_intent.succeeded` for type `deposit`, the webhook appends to `wallets/{uid}.depositRefs` (paymentIntentId, chargeId, amount, createdAt) and increments `availableDeposit`. Clients cannot write these fields (Firestore rules).

## Financial data model (wallets, deposits, payments)

- **Single source of truth for balance:** `wallets/{uid}`. The fields `availableDeposit` and `reservedDeposit` are the only place that defines a user’s current balance. These (and `depositRefs`) are backend-only in Firestore rules; only Cloud Functions (webhook, requestDepositWithdraw, forfeitOrRefund, etc.) update them.
- **One wallet per user:** Document ID = Firebase Auth UID. There should be exactly one wallet document per user. All app and backend code uses `wallets.doc(uid)`.
- **When multiple “financial” records exist for the same user:**
  - **wallets:** Exactly one document per user (document id = uid). No second “balance” record.
  - **payments:** Many documents per user. Each document is one payment event (deposit, listing_fee, buyer_commission, etc.). Used as a transaction log and for Stripe/webhook lookups, not for balance. Balance is never summed from payments.
  - **deposits:** One document per user when present: `deposits/{uid}`. This collection is legacy: the current Stripe deposit flow only updates `wallets` and `wallets/{uid}.depositRefs`; it does not write to `deposits`. The client-side `addDeposit` in FirestoreService still writes to both wallet and deposits, but with current rules clients cannot update `availableDeposit`, so that path is effectively legacy/test. The admin “Deposits” tab lists documents from `deposits` and for each row shows wallet balance (available/reserved); users who only ever deposited via Stripe may have no `deposits/{uid}` doc and won’t appear in that list unless the tab is later changed to list by wallets.
- **No double-counting:** Balance changes only in Cloud Functions (webhook increments, requestDepositWithdraw decrements, forfeitOrRefund adjusts). The webhook is idempotent: it skips if the payment intent is already in `depositRefs`. Clients cannot write `availableDeposit` or `depositRefs`, so the structure does not risk duplicated balances or double-counting deposits.
