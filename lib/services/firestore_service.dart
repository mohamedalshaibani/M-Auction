import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<bool> userExists(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.exists;
  }

  Future<void> createUserAndWallet({
    required String uid,
    required String displayName,
    required String phoneNumber,
  }) async {
    final batch = _firestore.batch();

    // Create user document
    final userRef = _firestore.collection('users').doc(uid);
    batch.set(userRef, {
      'displayName': displayName,
      'phoneNumber': phoneNumber,
      'role': 'user',
      'kycStatus': 'not_submitted',
      'vipDepositWaived': false,
      'strikeCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Create wallet document
    final walletRef = _firestore.collection('wallets').doc(uid);
    batch.set(walletRef, {
      'availableDeposit': 0.0,
      'lockedDeposit': 0.0,
      'reservedDeposit': 0.0,
      'depositStatus': 'none',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Stream<double> walletBalanceStream(String uid) {
    return _firestore
        .collection('wallets')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 0.0;
      final data = snapshot.data();
      return (data?['availableDeposit'] as num?)?.toDouble() ?? 0.0;
    });
  }

  Stream<String> kycStatusStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) return 'not_submitted';
      final data = snapshot.data();
      return data?['kycStatus'] as String? ?? 'not_submitted';
    });
  }

  // Get wallet document
  Future<DocumentSnapshot> getWallet(String uid) async {
    return await _firestore.collection('wallets').doc(uid).get();
  }

  // Stream wallet document
  Stream<DocumentSnapshot> streamWallet(String uid) {
    return _firestore.collection('wallets').doc(uid).snapshots();
  }

  // Add deposit (mock payment)
  Future<void> addDeposit({
    required String uid,
    required double amount,
    String? note,
  }) async {
    final batch = _firestore.batch();

    // Update wallet
    final walletRef = _firestore.collection('wallets').doc(uid);
    batch.update(walletRef, {
      'availableDeposit': FieldValue.increment(amount),
      'depositStatus': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Create/update deposit document
    final depositRef = _firestore.collection('deposits').doc(uid);
    batch.set(depositRef, {
      'amount': FieldValue.increment(amount),
      'status': 'held',
      'lastActionAt': FieldValue.serverTimestamp(),
      if (note != null) 'note': note,
    }, SetOptions(merge: true));

    await batch.commit();
  }

  // Lock deposit from available to locked
  Future<void> lockDeposit({
    required String uid,
    required double amount,
  }) async {
    await _firestore.collection('wallets').doc(uid).update({
      'availableDeposit': FieldValue.increment(-amount),
      'lockedDeposit': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Refund locked deposit to available
  Future<void> refundLockedDeposit({
    required String uid,
    required double amount,
  }) async {
    final batch = _firestore.batch();

    final walletRef = _firestore.collection('wallets').doc(uid);
    batch.update(walletRef, {
      'lockedDeposit': FieldValue.increment(-amount),
      'availableDeposit': FieldValue.increment(amount),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final depositRef = _firestore.collection('deposits').doc(uid);
    batch.update(depositRef, {
      'status': 'refunded',
      'lastActionAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // Forfeit locked deposit
  Future<void> forfeitLockedDeposit({
    required String uid,
    required double forfeitAmount,
  }) async {
    final batch = _firestore.batch();

    final walletRef = _firestore.collection('wallets').doc(uid);
    batch.update(walletRef, {
      'lockedDeposit': FieldValue.increment(-forfeitAmount),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final depositRef = _firestore.collection('deposits').doc(uid);
    batch.update(depositRef, {
      'status': 'forfeited',
      'lastActionAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // Get user document
  Future<DocumentSnapshot> getUser(String uid) async {
    return await _firestore.collection('users').doc(uid).get();
  }

  // Increment strike count
  Future<void> incrementStrikeCount(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'strikeCount': FieldValue.increment(1),
    });
  }

  // Get deposit document
  Future<DocumentSnapshot> getDeposit(String uid) async {
    return await _firestore.collection('deposits').doc(uid).get();
  }

  // Stream deposit document
  Stream<DocumentSnapshot> streamDeposit(String uid) {
    return _firestore.collection('deposits').doc(uid).snapshots();
  }

  // Get reservation for auction
  Future<DocumentSnapshot> getReservation(String uid, String auctionId) async {
    return await _firestore
        .collection('reservations')
        .doc(uid)
        .collection('active')
        .doc(auctionId)
        .get();
  }

  // Update reservation
  Future<void> updateReservation({
    required String uid,
    required String auctionId,
    required double requiredDeposit,
    required double lastBidAmount,
  }) async {
    await _firestore
        .collection('reservations')
        .doc(uid)
        .collection('active')
        .doc(auctionId)
        .set({
      'requiredDeposit': requiredDeposit,
      'lastBidAmount': lastBidAmount,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Release reservation
  Future<void> releaseReservation(String uid, String auctionId) async {
    final reservationDoc = await getReservation(uid, auctionId);
    if (!reservationDoc.exists) return;

    final reservationData = reservationDoc.data() as Map<String, dynamic>;
    final requiredDeposit =
        (reservationData['requiredDeposit'] as num?)?.toDouble() ?? 0.0;

    if (requiredDeposit > 0) {
      // Subtract from reservedDeposit
      await _firestore.collection('wallets').doc(uid).update({
        'reservedDeposit': FieldValue.increment(-requiredDeposit),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    // Delete reservation
    await _firestore
        .collection('reservations')
        .doc(uid)
        .collection('active')
        .doc(auctionId)
        .delete();
  }

  // Adjust reserved deposit
  Future<void> adjustReservedDeposit({
    required String uid,
    required double delta,
  }) async {
    if (delta != 0) {
      await _firestore.collection('wallets').doc(uid).update({
        'reservedDeposit': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // Move reservation to locked (on auction end for winner)
  Future<void> moveReservationToLocked(String uid, String auctionId) async {
    final reservationDoc = await getReservation(uid, auctionId);
    if (!reservationDoc.exists) return;

    final reservationData = reservationDoc.data() as Map<String, dynamic>;
    final requiredDeposit =
        (reservationData['requiredDeposit'] as num?)?.toDouble() ?? 0.0;

    if (requiredDeposit > 0) {
      final batch = _firestore.batch();

      // Move from reserved to locked
      final walletRef = _firestore.collection('wallets').doc(uid);
      batch.update(walletRef, {
        'reservedDeposit': FieldValue.increment(-requiredDeposit),
        'lockedDeposit': FieldValue.increment(requiredDeposit),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // Delete reservation
      final reservationRef = _firestore
          .collection('reservations')
          .doc(uid)
          .collection('active')
          .doc(auctionId);
      batch.delete(reservationRef);

      await batch.commit();
    }
  }
}
