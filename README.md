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
