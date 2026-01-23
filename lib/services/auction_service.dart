import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'admin_settings_service.dart';
import 'firestore_service.dart';
import 'contract_service.dart';
import 'payment_service.dart';

class AuctionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AdminSettingsService _adminSettings = AdminSettingsService();
  final FirestoreService _firestoreService = FirestoreService();
  final ContractService _contractService = ContractService();
  final PaymentService _paymentService = PaymentService();

  // Create draft auction
  Future<String> createDraftAuction({
    required String sellerId,
    required String category,
    required String brand,
    required String title,
    required String description,
    required String condition,
    required String itemIdentifier,
    required double startPrice,
    required int durationDays,
    List<String>? images,
  }) async {
    final minIncrement = await _adminSettings.getMinIncrementDefault();
    final windowMinutes = await _adminSettings.getAntiSnipingWindowMinutes();
    final extendMinutes = await _adminSettings.getAntiSnipingExtendMinutes();

    final auctionRef = _firestore.collection('auctions').doc();
    await auctionRef.set({
      'sellerId': sellerId,
      'category': category,
      'brand': brand,
      'title': title,
      'description': description,
      'condition': condition,
      'itemIdentifier': itemIdentifier,
      'images': images ?? [],
      'startPrice': startPrice,
      'currentPrice': startPrice,
      'currentWinnerId': null,
      'bidCount': 0,
      'state': 'DRAFT',
      'endsAt': null,
      'createdAt': FieldValue.serverTimestamp(),
      'minIncrement': minIncrement,
      'antiSnipingWindowMinutes': windowMinutes,
      'antiSnipingExtendMinutes': extendMinutes,
      'winnerContactReleased': false,
      'sellerConfirmedDelivery': false,
      'buyerConfirmedDelivery': false,
      'contactUnlockAt': null,
    });

    return auctionRef.id;
  }

  // Submit for approval
  Future<void> submitForApproval(String auctionId) async {
    await _firestore.collection('auctions').doc(auctionId).update({
      'state': 'PENDING_APPROVAL',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Admin approve and compute listing fee
  Future<void> adminApprove(String auctionId, int durationDays) async {
    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    final auctionDoc = await auctionRef.get();
    if (!auctionDoc.exists) throw Exception('Auction not found');
    final auctionData = auctionDoc.data();
    if (auctionData == null) throw Exception('Auction not found');

    final startPrice = (auctionData['startPrice'] as num).toDouble();
    final listingFee = await _adminSettings.computeListingFeePreview(
      startPrice: startPrice,
      durationDays: durationDays,
    );

    final endsAt = DateTime.now().add(Duration(days: durationDays));

    await auctionRef.update({
      'state': 'APPROVED_AWAITING_PAYMENT',
      'endsAt': Timestamp.fromDate(endsAt),
      'listingFeeAmount': listingFee,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Mark paid and activate (only if listing fee is paid)
  Future<void> markPaidAndActivate(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) throw Exception('Auction not found');

    final data = auctionDoc.data()!;
    final state = data['state'] as String;
    if (state != 'APPROVED_AWAITING_PAYMENT') {
      throw Exception('Auction must be in APPROVED_AWAITING_PAYMENT state');
    }

    final listingFeePaid = data['listingFeePaid'] as bool? ?? false;
    if (!listingFeePaid) {
      throw Exception('Listing fee must be paid before activation');
    }

    await _firestore.collection('auctions').doc(auctionId).update({
      'state': 'ACTIVE',
      'activatedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // Check deposit requirement with reservation logic
  Future<Map<String, dynamic>> checkDepositRequirement({
    required String bidderId,
    required double auctionPrice,
    String? auctionId,
  }) async {
    // Check if VIP waiver
    final userDoc = await _firestoreService.getUser(bidderId);
    if (userDoc.exists) {
      final userData = userDoc.data() as Map<String, dynamic>?;
      final vipWaived = userData?['vipDepositWaived'] as bool? ?? false;
      if (vipWaived) {
        return {
          'required': 0.0,
          'hasEnough': true,
          'vipWaived': true,
          'eligible': double.infinity,
          'bidLimit': double.infinity,
        };
      }
    }

    final requiredDeposit =
        await _adminSettings.computeRequiredDeposit(auctionPrice);
    if (requiredDeposit == 0.0) {
      return {
        'required': 0.0,
        'hasEnough': true,
        'vipWaived': false,
        'eligible': double.infinity,
        'bidLimit': double.infinity,
      };
    }

    final walletDoc = await _firestoreService.getWallet(bidderId);
    if (!walletDoc.exists) {
      return {
        'required': requiredDeposit,
        'hasEnough': false,
        'vipWaived': false,
        'eligible': 0.0,
        'bidLimit': 0.0,
      };
    }

    final walletData = walletDoc.data() as Map<String, dynamic>;
    final availableDeposit =
        (walletData['availableDeposit'] as num?)?.toDouble() ?? 0.0;
    final reservedDeposit =
        (walletData['reservedDeposit'] as num?)?.toDouble() ?? 0.0;

    // Get current auction reservation if exists
    double currentAuctionReserved = 0.0;
    if (auctionId != null) {
      final reservationDoc =
          await _firestoreService.getReservation(bidderId, auctionId);
      if (reservationDoc.exists) {
        final reservationData = reservationDoc.data() as Map<String, dynamic>;
        currentAuctionReserved =
            (reservationData['requiredDeposit'] as num?)?.toDouble() ?? 0.0;
      }
    }

    // Eligible = available - reserved + currentAuctionReserved
    final eligibleDeposit =
        availableDeposit - reservedDeposit + currentAuctionReserved;

    // Calculate max bid limit
    final bidLimit = await _adminSettings.calculateMaxBidLimit(eligibleDeposit);

    return {
      'required': requiredDeposit,
      'hasEnough': eligibleDeposit >= requiredDeposit,
      'vipWaived': false,
      'eligible': eligibleDeposit,
      'bidLimit': bidLimit,
      'currentReserved': currentAuctionReserved,
    };
  }

  // Place bid with transaction, anti-sniping, reservation logic, and outbid detection
  Future<void> placeBid({
    required String auctionId,
    required String bidderId,
    required double amount,
  }) async {
    final auctionRef = _firestore.collection('auctions').doc(auctionId);

    // Capture previous winner before transaction
    final auctionDocBefore = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDocBefore.exists) {
      throw Exception('Auction not found');
    }
    final dataBefore = auctionDocBefore.data() as Map<String, dynamic>;
    final previousWinnerId = dataBefore['currentWinnerId'] as String?;

    await _firestore.runTransaction((transaction) async {
      final auctionDoc = await transaction.get(auctionRef);
      if (!auctionDoc.exists) {
        throw Exception('Auction not found');
      }

      final data = auctionDoc.data() as Map<String, dynamic>;
      final state = data['state'] as String;
      if (state != 'ACTIVE') {
        throw Exception('Auction is not active');
      }

      final currentPrice = (data['currentPrice'] as num).toDouble();
      final minIncrement = (data['minIncrement'] as num).toDouble();

      if (amount < currentPrice + minIncrement) {
        throw Exception(
            'Bid must be at least ${currentPrice + minIncrement}');
      }

      final sellerId = data['sellerId'] as String;
      if (bidderId == sellerId) {
        throw Exception('Seller cannot bid on their own auction');
      }

      // Check deposit requirement with reservation logic
      final depositCheck = await checkDepositRequirement(
        bidderId: bidderId,
        auctionPrice: amount,
        auctionId: auctionId,
      );
      if (!depositCheck['vipWaived'] && !depositCheck['hasEnough']) {
        throw Exception(
            'Insufficient deposit. Required: ${depositCheck['required']}, Eligible: ${depositCheck['eligible']}');
      }

      // Get wallet and reservation
      final walletRef = _firestore.collection('wallets').doc(bidderId);
      final walletDoc = await transaction.get(walletRef);
      final walletData = (walletDoc.data() ?? {}) as Map<String, dynamic>;
      final availableDeposit =
          (walletData['availableDeposit'] as num?)?.toDouble() ?? 0.0;
      final reservedDeposit =
          (walletData['reservedDeposit'] as num?)?.toDouble() ?? 0.0;

      // Get current reservation for this auction
      final reservationRef = _firestore
          .collection('reservations')
          .doc(bidderId)
          .collection('active')
          .doc(auctionId);
      final reservationDoc = await transaction.get(reservationRef);
      final reservationData = reservationDoc.data() as Map<String, dynamic>?;
      final previousRequired = reservationDoc.exists
          ? (reservationData?['requiredDeposit'] as num?)?.toDouble() ?? 0.0
          : 0.0;

      final requiredDeposit = depositCheck['required'] as double;

      // Create bid
      final bidRef = _firestore
          .collection('auctions')
          .doc(auctionId)
          .collection('bids')
          .doc();
      transaction.set(bidRef, {
        'bidderId': bidderId,
        'amount': amount,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update auction
      final bidCount = (data['bidCount'] as num).toInt() + 1;
      transaction.update(auctionRef, {
        'currentPrice': amount,
        'currentWinnerId': bidderId,
        'bidCount': bidCount,
      });

      // Update reservation
      transaction.set(reservationRef, {
        'requiredDeposit': requiredDeposit,
        'lastBidAmount': amount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Adjust reservedDeposit by delta
      final delta = requiredDeposit - previousRequired;
      if (delta != 0) {
        transaction.update(walletRef, {
          'reservedDeposit': FieldValue.increment(delta),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // Anti-sniping: extend endsAt if needed
      final endsAt = data['endsAt'] as Timestamp?;
      if (endsAt != null) {
        final windowMinutes = (data['antiSnipingWindowMinutes'] as num).toInt();
        final extendMinutes =
            (data['antiSnipingExtendMinutes'] as num).toInt();

        final now = DateTime.now();
        final endsAtDate = endsAt.toDate();
        final timeLeft = endsAtDate.difference(now);

        if (timeLeft.inMinutes <= windowMinutes) {
          final newEndsAt = endsAtDate.add(Duration(minutes: extendMinutes));
          transaction.update(auctionRef, {
            'endsAt': Timestamp.fromDate(newEndsAt),
          });
        }
      }
    });

    // Handle outbid - release previous winner's reservation if they were outbid
    // previousWinnerId is captured before transaction, so it's the winner before this bid
    if (previousWinnerId != null &&
        previousWinnerId != bidderId &&
        previousWinnerId.isNotEmpty) {
      // Check if they're still the winner after transaction
      final auctionDocAfter = await _firestore.collection('auctions').doc(auctionId).get();
      if (auctionDocAfter.exists) {
        final dataAfter = auctionDocAfter.data() as Map<String, dynamic>;
        final currentWinnerId = dataAfter['currentWinnerId'] as String?;
        
        // If previous winner is no longer the winner, release their reservation
        if (currentWinnerId != previousWinnerId) {
          await _firestoreService.releaseReservation(previousWinnerId, auctionId);
        }
      }
    }
  }

  // Check and end auction if needed (call before displaying)
  Future<void> checkAndEndAuction(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) return;

    final data = auctionDoc.data()!;
    final state = data['state'] as String;
    if (state != 'ACTIVE') return;

    final endsAt = data['endsAt'] as Timestamp?;
    if (endsAt == null) return;

    final now = DateTime.now();
    final endDate = endsAt.toDate();

    if (now.isAfter(endDate)) {
      await _endAuction(auctionId, data);
    }
  }

    // End auction and handle deposit hold
  Future<void> _endAuction(String auctionId, Map<String, dynamic> auctionData) async {
    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    final winnerId = auctionData['currentWinnerId'] as String?;
    final currentPrice = (auctionData['currentPrice'] as num?)?.toDouble() ?? 0.0;
    final sellerId = auctionData['sellerId'] as String? ?? '';
    final endsAt = auctionData['endsAt'] as Timestamp?;

    if (winnerId == null || winnerId.isEmpty) {
      // No winner - release all reservations and end
      await _releaseAllReservationsForAuction(auctionId);
      await auctionRef.update({
        'state': 'ENDED',
      });
      return;
    }

    // Get finalPrice (use existing if set, otherwise use currentPrice)
    final finalPrice = (auctionData['finalPrice'] as num?)?.toDouble() ?? currentPrice;
    
    // Compute required deposit
    final requiredDeposit = await _adminSettings.computeRequiredDeposit(finalPrice);
    final deadlineHours = await _adminSettings.getWinnerDeadlineHours();
    
    // Calculate winnerDeadlineAt = endsAt + deadlineHours
    final deadlineAt = endsAt != null
        ? endsAt.toDate().add(Duration(hours: deadlineHours))
        : DateTime.now().add(Duration(hours: deadlineHours));

    // Check VIP waiver
    final userDoc = await _firestore.collection('users').doc(winnerId).get();
    final userData = userDoc.data() as Map<String, dynamic>?;
    final vipWaived = userData?['vipDepositWaived'] as bool? ?? false;

    // Hold deposit in transaction
    await _firestore.runTransaction((tx) async {
      final walletRef = _firestore.collection('wallets').doc(winnerId);
      final walletDoc = await tx.get(walletRef);
      
      if (!walletDoc.exists) {
        throw Exception('Winner wallet not found');
      }
      
      final walletData = walletDoc.data() as Map<String, dynamic>;
      final availableDeposit = (walletData['availableDeposit'] as num?)?.toDouble() ?? 0.0;
      final reservedDeposit = (walletData['reservedDeposit'] as num?)?.toDouble() ?? 0.0;
      
      // Check if deposit can be held (VIP waived or sufficient funds)
      if (vipWaived || availableDeposit >= requiredDeposit) {
        if (!vipWaived) {
          // Move from availableDeposit to reservedDeposit
          tx.update(walletRef, {
            'availableDeposit': FieldValue.increment(-requiredDeposit),
            'reservedDeposit': FieldValue.increment(requiredDeposit),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        
        // Update auction with deposit held
        tx.update(auctionRef, {
          'state': 'ENDED',
          'depositRequired': requiredDeposit,
          'depositHeld': vipWaived ? 0.0 : requiredDeposit,
          'depositStatus': vipWaived ? 'waived' : 'held',
          'winnerDeadlineAt': Timestamp.fromDate(deadlineAt),
          'winnerDeadlineHours': deadlineHours,
        });
      } else {
        // Insufficient deposit
        tx.update(auctionRef, {
          'state': 'ENDED',
          'depositRequired': requiredDeposit,
          'depositHeld': 0.0,
          'depositStatus': 'insufficient',
          'winnerDeadlineAt': Timestamp.fromDate(deadlineAt),
          'winnerDeadlineHours': deadlineHours,
        });
      }
    });

    // Release all other reservations for this auction
    await _releaseAllReservationsForAuction(auctionId, excludeUid: winnerId);

    // Create contract
    await _contractService.createContract(
      auctionId: auctionId,
      sellerId: sellerId,
      buyerId: winnerId,
    );
  }

  // Release all reservations for an auction (except excludeUid if provided)
  Future<void> _releaseAllReservationsForAuction(
    String auctionId, {
    String? excludeUid,
  }) async {
    // Get all users who have reservations for this auction
    // Note: This is a limitation - we'd need to query all reservations
    // In production, you might want to store auctionId -> [uid] mapping
    // For MVP, we'll handle it per-user when they interact
    // This method is called on auction end, so we can iterate known bidders
    final bidsSnapshot = await _firestore
        .collection('auctions')
        .doc(auctionId)
        .collection('bids')
        .get();

    final uniqueBidders = <String>{};
    for (final bidDoc in bidsSnapshot.docs) {
      final bidData = bidDoc.data();
      final bidderId = bidData['bidderId'] as String?;
      if (bidderId != null && bidderId != excludeUid) {
        uniqueBidders.add(bidderId);
      }
    }

    // Release reservations for all bidders except winner
    for (final uid in uniqueBidders) {
      await _firestoreService.releaseReservation(uid, auctionId);
    }
  }

  // Winner confirms purchase
  Future<void> winnerConfirmPurchase(String auctionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');

    // Fetch commission settings BEFORE transaction (cached in memory)
    final buyerPercent = await _adminSettings.getBuyerCommissionPercent();
    final buyerMin = await _adminSettings.getBuyerCommissionMin();
    final sellerPercent = await _adminSettings.getSellerCommissionPercent();
    final sellerMin = await _adminSettings.getSellerCommissionMin();

    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    String sellerId = '';
    String winnerId = '';

    await _firestore.runTransaction((tx) async {
      final auctionSnap = await tx.get(auctionRef);
      if (!auctionSnap.exists) throw Exception('Auction not found');

      final data = auctionSnap.data() as Map<String, dynamic>;
      
      // Check if already confirmed - prevent duplicate writes
      final alreadyConfirmed = data['buyerConfirmedPurchase'] as bool? ?? false;
      if (alreadyConfirmed) {
        // Already confirmed, do nothing
        return;
      }

      final state = data['state'] as String? ?? 'UNKNOWN';
      if (state != 'ENDED') throw Exception('Auction is not ended');

      sellerId = data['sellerId'] as String? ?? '';
      winnerId = data['currentWinnerId'] as String? ?? '';
      if (winnerId.isEmpty || winnerId != user.uid) {
        throw Exception('Only winner can confirm purchase');
      }

      // Get currentPrice as finalPrice at moment of confirm
      final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
      if (currentPrice <= 0) {
        throw Exception('Invalid auction price');
      }
      final finalPrice = currentPrice;

      // Round to 2 decimals helper
      double round2(double v) {
        return double.parse(v.toStringAsFixed(2));
      }

      // Compute commissions: max(percentage, minimum)
      final buyerPctDue = finalPrice * (buyerPercent / 100.0);
      final sellerPctDue = finalPrice * (sellerPercent / 100.0);
      final buyerDue = round2(buyerPctDue > buyerMin ? buyerPctDue : buyerMin);
      final sellerDue = round2(sellerPctDue > sellerMin ? sellerPctDue : sellerMin);

      // Update auction in single transaction with all commission fields
      final updateData = {
        'buyerConfirmedPurchase': true,
        'purchaseConfirmedAt': FieldValue.serverTimestamp(),
        'finalPrice': round2(finalPrice),
        'buyerCommissionDue': buyerDue,
        'sellerCommissionDue': sellerDue,
        'buyerCommissionPaid': false,
        'sellerCommissionPaid': false,
        'commissionStatus': 'pending',
        'commissionCalculatedAt': FieldValue.serverTimestamp(),
      };
      
      tx.update(auctionRef, updateData);
      
      // Log for debugging (will appear in Firestore console)
      print('Commission calculated for auction $auctionId:');
      print('  finalPrice: ${round2(finalPrice)}');
      print('  buyerCommissionDue: $buyerDue');
      print('  sellerCommissionDue: $sellerDue');
    });

    // Ensure contract exists (outside transaction)
    if (sellerId.isNotEmpty && winnerId.isNotEmpty) {
      await _contractService.createContract(
        auctionId: auctionId,
        sellerId: sellerId,
        buyerId: winnerId,
      );
    }
  }

  // Seller accepts contract terms (auto-accept for MVP)
  Future<void> sellerAcceptTerms(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) throw Exception('Auction not found');

    final data = auctionDoc.data()!;
    final sellerId = data['sellerId'] as String? ?? '';

    await _contractService.acceptTerms(
      auctionId: auctionId,
      userId: sellerId,
      isSeller: true,
    );
  }

  // Report no response and forfeit deposit - uses Stripe forfeit
  Future<void> reportNoResponse(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) throw Exception('Auction not found');

    final data = auctionDoc.data()!;
    final state = data['state'] as String;
    if (state != 'ENDED') throw Exception('Auction is not ended');

    final sellerId = data['sellerId'] as String?;
    if (sellerId != FirebaseAuth.instance.currentUser?.uid) {
      throw Exception('Only seller can report no response');
    }

    final winnerId = data['currentWinnerId'] as String?;
    if (winnerId == null) throw Exception('No winner');

    final contactUnlockAt = data['contactUnlockAt'] as Timestamp?;
    if (contactUnlockAt != null) {
      final deadline = contactUnlockAt.toDate();
      final now = DateTime.now();
      if (now.isBefore(deadline)) {
        throw Exception('Deadline has not passed yet');
      }
    }

    final walletDoc = await _firestoreService.getWallet(winnerId);
    final walletData = walletDoc.data() as Map<String, dynamic>?;
    final lockedDeposit = (walletData?['lockedDeposit'] as num?)?.toDouble() ?? 0.0;

    if (lockedDeposit > 0) {
      final forfeitAmount = await _adminSettings.computeForfeitAmount(lockedDeposit);
      final refundAmount = lockedDeposit - forfeitAmount;

      // Forfeit amount via PaymentService
      if (forfeitAmount > 0) {
        await _paymentService.forfeitOrRefund(
          uid: winnerId,
          auctionId: auctionId,
          action: 'forfeit',
          amount: forfeitAmount,
        );
      }

      // Refund remaining via PaymentService
      if (refundAmount > 0) {
        await _paymentService.forfeitOrRefund(
          uid: winnerId,
          auctionId: auctionId,
          action: 'refund',
          amount: refundAmount,
        );
      }
    }

    // Increment strike count
    await _firestoreService.incrementStrikeCount(winnerId);
  }

  // Confirm delivery (seller or buyer)
  Future<void> confirmDelivery({
    required String auctionId,
    required bool isSeller,
  }) async {
    final auctionRef = _firestore.collection('auctions').doc(auctionId);
    
    // Use transaction to atomically update and check for deliveryConfirmedAt
    await _firestore.runTransaction((tx) async {
      final auctionDoc = await tx.get(auctionRef);
      if (!auctionDoc.exists) {
        throw Exception('Auction not found');
      }
      
      final data = auctionDoc.data() as Map<String, dynamic>;
      
      // Prepare update data
      final updateData = <String, dynamic>{};
      
      if (isSeller) {
        updateData['sellerConfirmedDelivery'] = true;
      } else {
        updateData['buyerConfirmedDelivery'] = true;
      }
      
      // Check if both are confirmed and deliveryConfirmedAt is not set
      final sellerConfirmed = isSeller 
          ? true 
          : (data['sellerConfirmedDelivery'] as bool? ?? false);
      final buyerConfirmed = isSeller 
          ? (data['buyerConfirmedDelivery'] as bool? ?? false)
          : true;
      
      final deliveryConfirmedAt = data['deliveryConfirmedAt'];
      
      if (sellerConfirmed && buyerConfirmed && deliveryConfirmedAt == null) {
        updateData['deliveryConfirmedAt'] = FieldValue.serverTimestamp();
      }
      
      tx.update(auctionRef, updateData);
    });
  }

  // Request deposit refund (after both confirmed delivery) - uses Stripe refund
  Future<void> requestDepositRefund(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) throw Exception('Auction not found');

    final data = auctionDoc.data()!;
    final sellerConfirmed = data['sellerConfirmedDelivery'] as bool? ?? false;
    final buyerConfirmed = data['buyerConfirmedDelivery'] as bool? ?? false;

    if (!sellerConfirmed || !buyerConfirmed) {
      throw Exception('Both parties must confirm delivery');
    }

    final winnerId = data['currentWinnerId'] as String?;
    if (winnerId == null) throw Exception('No winner');

    final walletDoc = await _firestoreService.getWallet(winnerId);
    final walletData = walletDoc.data() as Map<String, dynamic>?;
    final lockedDeposit = (walletData?['lockedDeposit'] as num?)?.toDouble() ?? 0.0;

    if (lockedDeposit > 0) {
      // Use PaymentService to refund via Stripe
      await _paymentService.forfeitOrRefund(
        uid: winnerId,
        auctionId: auctionId,
        action: 'refund',
        amount: lockedDeposit,
      );
    }
  }

  // Check if contact should be released
  Future<bool> shouldReleaseContact(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) return false;

    final data = auctionDoc.data()!;
    final state = data['state'] as String;
    if (state != 'ENDED') return false;

    final winnerReleased = data['winnerContactReleased'] as bool? ?? false;
    if (winnerReleased) return true;

    final contactUnlockAt = data['contactUnlockAt'] as Timestamp?;
    if (contactUnlockAt == null) return false;

    final now = DateTime.now();
    final deadline = contactUnlockAt.toDate();

    if (now.isBefore(deadline)) return false;

    // Check if both parties accepted contract
    final bothAccepted = await _contractService.bothPartiesAccepted(auctionId);
    return bothAccepted;
  }

  // Stream active auctions
  Stream<QuerySnapshot> streamActiveAuctions() {
    return _firestore
        .collection('auctions')
        .where('state', isEqualTo: 'ACTIVE')
        .snapshots();
  }

  // Stream active auctions - NO orderBy to avoid any index requirements
  // All filtering (category) and sorting (endsAt) is done in memory in the UI layer
  Stream<QuerySnapshot> streamActiveAuctionsFiltered({
    String? category,
    int limit = 50,
  }) {
    // Simple query with only state filter - no orderBy, no category filter in Firestore
    // This guarantees no composite index is needed
    return _firestore
        .collection('auctions')
        .where('state', isEqualTo: 'ACTIVE')
        .limit(limit)
        .snapshots();
  }

  // Stream seller auctions
  Stream<QuerySnapshot> streamSellerAuctions(String sellerId) {
    return _firestore
        .collection('auctions')
        .where('sellerId', isEqualTo: sellerId)
        .snapshots();
  }

  // Stream pending approval auctions (no orderBy to avoid index requirement)
  Stream<QuerySnapshot> streamPendingApprovalAuctions() {
    return _firestore
        .collection('auctions')
        .where('state', isEqualTo: 'PENDING_APPROVAL')
        .snapshots();
  }

  // Stream won auctions (where currentWinnerId == uid)
  Stream<QuerySnapshot> streamWonAuctions(String uid) {
    return _firestore
        .collection('auctions')
        .where('currentWinnerId', isEqualTo: uid)
        .snapshots();
  }

  // Get auction document
  Future<DocumentSnapshot> getAuction(String auctionId) async {
    return await _firestore.collection('auctions').doc(auctionId).get();
  }

  // Stream auction document
  Stream<DocumentSnapshot> streamAuction(String auctionId) {
    return _firestore.collection('auctions').doc(auctionId).snapshots();
  }

  // Stream bids for auction
  Stream<QuerySnapshot> streamBids(String auctionId, {int limit = 10}) {
    return _firestore
        .collection('auctions')
        .doc(auctionId)
        .collection('bids')
        .orderBy('amount', descending: true)
        .limit(limit)
        .snapshots();
  }

  // Check if user is admin (reads from Firestore)
  Future<bool> isAdmin(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) return false;
    final userData = userDoc.data() as Map<String, dynamic>?;
    final role = userData?['role'] as String?;
    return role == 'admin';
  }

  // Release contact info (called when both parties accept terms)
  Future<void> releaseContact(String auctionId) async {
    final auctionDoc = await _firestore.collection('auctions').doc(auctionId).get();
    if (!auctionDoc.exists) throw Exception('Auction not found');

    final data = auctionDoc.data()!;
    final buyerConfirmed = data['buyerConfirmedPurchase'] as bool? ?? false;
    if (!buyerConfirmed) throw Exception('Buyer must confirm purchase first');

    // Check if both parties accepted terms
    final bothAccepted = await _contractService.bothPartiesAccepted(auctionId);
    if (!bothAccepted) throw Exception('Both parties must accept terms');

    // Use transaction to ensure atomic update
    await _firestore.runTransaction((transaction) async {
      final auctionRef = _firestore.collection('auctions').doc(auctionId);
      final contractRef = _firestore.collection('contracts').doc(auctionId);
      
      final auctionSnapshot = await transaction.get(auctionRef);
      final contractSnapshot = await transaction.get(contractRef);
      
      if (!auctionSnapshot.exists || !contractSnapshot.exists) {
        throw Exception('Auction or contract not found');
      }

      final auctionData = auctionSnapshot.data() as Map<String, dynamic>;
      final contractData = contractSnapshot.data() as Map<String, dynamic>;

      final confirmed = auctionData['buyerConfirmedPurchase'] as bool? ?? false;
      final sellerAccepted = contractData['termsAcceptedSeller'] as bool? ?? false;
      final buyerAccepted = contractData['termsAcceptedBuyer'] as bool? ?? false;

      if (confirmed && sellerAccepted && buyerAccepted) {
        transaction.update(auctionRef, {
          'winnerContactReleased': true,
        });
      } else {
        throw Exception('Cannot release contact: conditions not met');
      }
    });
  }

  // Admin override: force release contact
  Future<void> forceReleaseContact(String auctionId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }
    if (!await isAdmin(user.uid)) {
      throw Exception('Only admin can force release contact');
    }

    await _firestore.collection('auctions').doc(auctionId).update({
      'winnerContactReleased': true,
    });
  }

  // Get user phone number
  Future<String?> getUserPhone(String uid) async {
    final userDoc = await _firestore.collection('users').doc(uid).get();
    if (!userDoc.exists) return null;
    return userDoc.data()?['phoneNumber'] as String?;
  }
}
