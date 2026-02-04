// Stub file - should not be used, but provides fallback
import 'package:flutter/material.dart';
import '../widgets/unified_app_bar.dart';

class PaymentPageImpl extends StatelessWidget {
  final String type;
  final double amount;
  final String? auctionId;
  final String title;

  const PaymentPageImpl({
    super.key,
    required this.type,
    required this.amount,
    this.auctionId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: UnifiedAppBar(title: title),
      body: const Center(
        child: Text('Payment not available on this platform'),
      ),
    );
  }
}
