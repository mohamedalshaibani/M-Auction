// Cross-platform payment page with conditional imports
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// Conditional imports - web uses web implementation, mobile uses mobile implementation
import 'payment_page_stub.dart'
    if (dart.library.html) 'payment_page_web.dart'
    if (dart.library.io) 'payment_page_mobile.dart';

class PaymentPage extends StatelessWidget {
  final String type; // 'deposit', 'listing_fee', or 'buyer_commission'
  final double amount;
  final String? auctionId;
  final String title;

  const PaymentPage({
    super.key,
    required this.type,
    required this.amount,
    this.auctionId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    // Use the conditionally imported implementation
    return PaymentPageImpl(
      type: type,
      amount: amount,
      auctionId: auctionId,
      title: title,
    );
  }
}
