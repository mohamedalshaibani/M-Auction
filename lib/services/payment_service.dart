import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  static String? _stripePublishableKey;

  // Set Stripe publishable key (public, safe to use in Flutter)
  static void setPublishableKey(String key) {
    _stripePublishableKey = key;
  }

  static String? get publishableKey => _stripePublishableKey;

  // Create PaymentIntent via Cloud Function
  // Supported types: 'deposit', 'listing_fee', 'buyer_commission', 'seller_commission'
  Future<Map<String, dynamic>> createPaymentIntent({
    required String type,
    required double amount,
    String currency = 'aed',
    String? auctionId,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('User must be authenticated');
    }

    // Validate amount is positive and finite
    if (amount <= 0 || !amount.isFinite) {
      throw Exception('Amount must be a positive number, got: $amount');
    }

    try {
      final callable = _functions.httpsCallable('createPaymentIntent');
      
      // Send amount as number (major currency units - e.g., 10.50 AED)
      // Backend will convert to minor units (fils) for Stripe
      final result = await callable.call({
        'type': type,
        'amount': amount, // Send as double, backend converts to integer minor units
        'currency': currency,
        if (auctionId != null) 'auctionId': auctionId,
      });

      return {
        'clientSecret': result.data['clientSecret'] as String,
        'paymentId': result.data['paymentId'] as String,
      };
    } on FirebaseFunctionsException catch (e) {
      // Extract detailed error message from Cloud Function
      final errorMessage = e.message ?? 'Unknown error';
      final errorCode = e.code;  // code is non-nullable in FirebaseFunctionsException
      final errorDetails = e.details?.toString() ?? '';
      
      throw Exception('Failed to create payment intent ($errorCode): $errorMessage${errorDetails.isNotEmpty ? ' - $errorDetails' : ''}');
    } catch (e) {
      throw Exception('Failed to create payment intent: $e');
    }
  }

  // Forfeit or refund (admin only)
  Future<Map<String, dynamic>> forfeitOrRefund({
    required String uid,
    required String auctionId,
    required String action, // 'forfeit' or 'refund'
    required double amount,
  }) async {
    try {
      final callable = _functions.httpsCallable('forfeitOrRefund');
      final result = await callable.call({
        'uid': uid,
        'auctionId': auctionId,
        'action': action,
        'amount': amount,
      });

      return {
        'status': result.data['status'] as String,
        'paymentId': result.data['paymentId'] as String?,
        'refundId': result.data['refundId'] as String?,
      };
    } catch (e) {
      throw Exception('Failed to $action payment: $e');
    }
  }

  /// Sync listing fee payment from Stripe (call after user returns from successful payment).
  /// Updates auction to paid + ACTIVE so the list reflects immediately even if webhook was slow.
  Future<bool> syncListingFeePayment(String auctionId) async {
    try {
      final callable = _functions.httpsCallable('syncListingFeePayment');
      final result = await callable.call({'auctionId': auctionId});
      final data = result.data as Map<String, dynamic>?;
      return data?['updated'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  // Get payment status
  Stream<DocumentSnapshot> streamPayment(String paymentId) {
    return FirebaseFirestore.instance
        .collection('payments')
        .doc(paymentId)
        .snapshots();
  }
}
