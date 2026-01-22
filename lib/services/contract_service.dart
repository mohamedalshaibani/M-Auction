import 'package:cloud_firestore/cloud_firestore.dart';

class ContractService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create contract document
  Future<void> createContract({
    required String auctionId,
    required String sellerId,
    required String buyerId,
  }) async {
    final contractRef = _firestore.collection('contracts').doc(auctionId);
    final existingDoc = await contractRef.get();
    
    // Only set default values if contract doesn't exist
    if (!existingDoc.exists) {
      await contractRef.set({
        'auctionId': auctionId,
        'sellerId': sellerId,
        'buyerId': buyerId,
        'termsAcceptedSeller': false,
        'termsAcceptedBuyer': false,
        'acceptedAtSeller': null,
        'acceptedAtBuyer': null,
        'contractVersion': '1.0',
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } else {
      // Update existing contract without overwriting acceptance
      await contractRef.set({
        'auctionId': auctionId,
        'sellerId': sellerId,
        'buyerId': buyerId,
      }, SetOptions(merge: true));
    }
  }

  // Accept terms (seller or buyer)
  Future<void> acceptTerms({
    required String auctionId,
    required String userId,
    required bool isSeller,
  }) async {
    final contractRef = _firestore.collection('contracts').doc(auctionId);
    if (isSeller) {
      await contractRef.update({
        'termsAcceptedSeller': true,
        'acceptedAtSeller': FieldValue.serverTimestamp(),
      });
    } else {
      await contractRef.update({
        'termsAcceptedBuyer': true,
        'acceptedAtBuyer': FieldValue.serverTimestamp(),
      });
    }
  }

  // Get contract
  Future<DocumentSnapshot> getContract(String auctionId) async {
    return await _firestore.collection('contracts').doc(auctionId).get();
  }

  // Stream contract
  Stream<DocumentSnapshot> streamContract(String auctionId) {
    return _firestore.collection('contracts').doc(auctionId).snapshots();
  }

  // Check if both parties accepted
  Future<bool> bothPartiesAccepted(String auctionId) async {
    final contract = await getContract(auctionId);
    if (!contract.exists) return false;

    final data = contract.data() as Map<String, dynamic>;
    final sellerAccepted = data['termsAcceptedSeller'] as bool? ?? false;
    final buyerAccepted = data['termsAcceptedBuyer'] as bool? ?? false;

    return sellerAccepted && buyerAccepted;
  }
}
