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
