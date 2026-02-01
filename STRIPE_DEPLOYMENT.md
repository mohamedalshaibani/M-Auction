# Stripe Payments Deployment Guide

## Prerequisites

1. Install Firebase CLI: `npm install -g firebase-tools`
2. Install Node.js 18 or higher
3. Have a Stripe account and API keys

## Setup

### 1. Configure Stripe Keys in Firebase Functions

#### Option A: Using Firebase Functions Config (Development)

```bash
# Set Stripe secret key
firebase functions:config:set stripe.secret_key="sk_test_YOUR_SECRET_KEY"

# Set Stripe webhook secret (after creating webhook endpoint)
firebase functions:config:set stripe.webhook_secret="whsec_YOUR_WEBHOOK_SECRET"
```

#### Option B: Using Firebase Secrets (Production - Recommended)

```bash
# Set secret key (will prompt for value)
echo "sk_live_YOUR_SECRET_KEY" | firebase functions:secrets:set STRIPE_SECRET_KEY

# Set webhook secret (will prompt for value)
echo "whsec_YOUR_WEBHOOK_SECRET" | firebase functions:secrets:set STRIPE_WEBHOOK_SECRET
```

**Note**: The code checks both `functions.config().stripe.secret_key` and `process.env.STRIPE_SECRET_KEY`, so either method works.

### 2. Install Function Dependencies

```bash
cd functions
npm install
cd ..
```

### 3. Set Stripe Publishable Key in the App

The Stripe publishable key is public and safe to use in the client. The app loads it in this order:

**Option A: Firestore (recommended for production)**

Set the key in Firestore so it can be changed without rebuilding the app:

1. Open Firebase Console → Firestore.
2. Create or open the document `adminSettings` → `main`.
3. Add a field: `stripePublishableKey` (string) with value `pk_test_...` or `pk_live_...`.

The app reads this at startup and again when opening the payment screen.

**Option B: Dart define (for local runs or CI/CD)**

```bash
# When running (e.g. iOS Simulator)
flutter run -d "iPhone 17 Pro" --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_YOUR_PUBLISHABLE_KEY

# When building web
flutter build web --dart-define=STRIPE_PUBLISHABLE_KEY=pk_live_YOUR_PUBLISHABLE_KEY
```

If both are set, the dart-define value overrides Firestore.

**For web**: The code uses Stripe.js (loaded in `web/index.html`) and mounts Payment Element in Flutter web using `HtmlElementView`.

### 4. Create Stripe Webhook Endpoint

1. Go to Stripe Dashboard → Developers → Webhooks
2. Click "Add endpoint"
3. Endpoint URL: `https://YOUR_REGION-YOUR_PROJECT.cloudfunctions.net/stripeWebhook`
   - Replace `YOUR_REGION` with your Firebase Functions region (e.g., `us-central1`)
   - Replace `YOUR_PROJECT` with your Firebase project ID
   - Example: `https://us-central1-luxuryauction-e9c56.cloudfunctions.net/stripeWebhook`
4. Select events to listen to:
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `charge.refunded`
5. Copy the webhook signing secret (starts with `whsec_`)
6. Set it in Firebase: `firebase functions:config:set stripe.webhook_secret="whsec_..."`

### 5. Deploy Functions

```bash
# Deploy all functions
firebase deploy --only functions

# Or deploy specific functions
firebase deploy --only functions:createPaymentIntent
firebase deploy --only functions:forfeitOrRefund
firebase deploy --only functions:stripeWebhook
```

### 6. Deploy Firestore Rules

```bash
firebase deploy --only firestore:rules
```

## Payment Flow

### Deposit Top-up
1. User clicks "Add Deposit" in WalletPage
2. User enters amount and clicks button
3. Opens PaymentPage with Stripe Payment Element
4. User enters card details and confirms
5. Payment processed via Stripe.js
6. Webhook updates `payments/{paymentId}` status to "succeeded"
7. Webhook increments `wallets/{uid}.availableDeposit`

### Listing Fee Payment
1. Admin approves auction → state becomes "APPROVED_AWAITING_PAYMENT"
2. Seller sees "Pay Listing Fee" button in My Auctions
3. Opens PaymentPage with listing fee amount
4. User pays via Stripe Payment Element
5. Webhook updates payment status and sets `auctions/{auctionId}.listingFeePaid=true`
6. Webhook activates auction (sets state to "ACTIVE")

### Forfeit/Refund
1. Admin calls `forfeitOrRefund` Cloud Function from auction detail page
2. Function finds related payment and processes Stripe refund/forfeit
3. Updates wallet balances accordingly

## Testing

### Test Payment Flow

1. Use Stripe test cards: https://stripe.com/docs/testing
   - Success: `4242 4242 4242 4242`
   - Decline: `4000 0000 0000 0002`
   - Use any future expiry, any CVC, any ZIP
2. Test deposit top-up from Wallet page
3. Test listing fee payment from My Auctions page
4. Check Firestore `payments` collection for payment records
5. Verify wallet balances update via webhook

### Test Webhook Locally

```bash
# Start emulator
firebase emulators:start --only functions

# Forward webhook to local emulator (in another terminal)
stripe listen --forward-to localhost:5001/YOUR_PROJECT/us-central1/stripeWebhook
```

## Production Checklist

- [ ] Use production Stripe keys (`sk_live_...` and `pk_live_...`)
- [ ] Set webhook endpoint to production URL
- [ ] Test payment flows end-to-end
- [ ] Monitor Firebase Functions logs
- [ ] Monitor Stripe Dashboard for payment activity
- [ ] Set up error alerts in Firebase Console
- [ ] Verify webhook signature verification works
- [ ] Test refund/forfeit flows

## Important Notes

- **Never commit Stripe secret keys** to version control
- Wallet balances are only updated via webhooks (backend only)
- Payment status is tracked in `payments/{paymentId}` collection
- Listing fee must be paid before auction can be activated (handled by webhook)
- Deposit refunds/forfeits handled by admin via Cloud Functions
- Stripe Payment Element requires Stripe.js to be loaded in `web/index.html` (already added)
- For web, Payment Element is mounted using `HtmlElementView` with `PlatformViewRegistry`

## Troubleshooting

### Webhook not receiving events
- Verify webhook URL is correct and accessible
- Check webhook secret matches in Stripe Dashboard and Firebase config
- Check Firebase Functions logs: `firebase functions:log`
- Verify webhook signature verification in code

### Payment Element not showing
- Check browser console for Stripe.js errors
- Verify Stripe.js is loaded in `web/index.html`
- Check publishable key is set correctly
- Verify `PlatformViewRegistry.registerViewFactory` is called

### Payment not updating wallet
- Check webhook events in Stripe Dashboard
- Verify webhook handler is processing events correctly
- Check Firestore rules allow webhook to write payments and wallets
- Verify payment status in `payments/{paymentId}` collection

### Functions deployment fails
- Ensure Node.js 18+ is installed
- Check `functions/package.json` dependencies are correct
- Verify Firebase CLI is up to date: `npm install -g firebase-tools@latest`
- Check `functions/index.js` for syntax errors

## Web Payment Element Implementation

The PaymentPage uses:
- Stripe.js loaded via `<script>` tag in `web/index.html`
- `HtmlElementView` with `PlatformViewRegistry.registerViewFactory` to mount Payment Element
- Direct DOM manipulation via `dart:html` to initialize Stripe.js
- Real-time payment status polling via Firestore stream
- Webhook-driven status updates (backend)

If Payment Element integration is blocked, the code structure allows easy fallback to Stripe Checkout Session redirect without changing Firestore logic.
