# luxury_auction_app

A luxury auction Flutter application with Firebase authentication, Firestore database, and real-time bidding.

## Getting Started

This project uses Flutter and Firebase (Firestore, Auth, Storage).

A few resources to get you started:
- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Firebase Security Rules Deployment

This app uses Firebase Firestore and Storage security rules. To deploy the rules:

### Prerequisites
1. Install Firebase CLI: `npm install -g firebase-tools`
2. Login to Firebase: `firebase login`
3. Initialize Firebase (if not already done): `firebase init`

### Deploy Rules

**Deploy Firestore rules:**
```bash
firebase deploy --only firestore:rules
```

**Deploy Storage rules:**
```bash
firebase deploy --only storage
```

**Deploy both:**
```bash
firebase deploy --only firestore:rules,storage
```

### Rules Files
- `firestore.rules` - Firestore security rules for collections (users, auctions, bids, wallets, deposits, reservations, contracts, adminSettings)
- `storage.rules` - Firebase Storage rules for image uploads (user_uploads/{uid}/...)

### Admin Setup
To set a user as admin, update the user document in Firestore:
```
users/{uid}.role = "admin"
```

Only users with `role == "admin"` can access the Admin Panel and perform admin actions.

### Testing data: 30 ACTIVE auctions
To seed 30 ACTIVE auctions in Firestore so they appear in Home, Explore, and open correctly on Auction Detail:

1. **Service account**: In [Firebase Console](https://console.firebase.google.com) → Project settings → Service accounts → **Generate new private key**. Save the JSON file (e.g. `serviceAccountKey.json`) in the project root. **Do not commit this file.**

2. **Run the seed script** from the **`functions`** directory (so `firebase-admin` is found):
   ```bash
   cd functions
   GOOGLE_APPLICATION_CREDENTIALS=../serviceAccountKey.json node scripts/seed_auctions.js
   ```
   Or use the npm script:
   ```bash
   cd functions
   GOOGLE_APPLICATION_CREDENTIALS=../serviceAccountKey.json npm run seed-auctions
   ```

3. **Optional**: `SEED_SELLER_UID=someUserUid` — use an existing user UID as seller for all seed auctions; otherwise the script uses the first user in the `users` collection or a placeholder.

4. **After seeding**: Restart or refresh the app. You should see 30 ACTIVE auctions in **Home** (carousel and categories) and **Explore**, and each item should open **Auction Detail** without errors. The seed creates 5 auctions per category (Watches, Bags, Fashion, Jewelry, Accessories, Collectibles) with 1–3 images each and future `endsAt` (mix of ending soon and later).
