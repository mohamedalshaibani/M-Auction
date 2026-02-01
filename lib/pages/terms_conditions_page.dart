import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';

/// Terms & Conditions: from Firestore content/terms or static fallback.
/// Agreement step exists only during auction creation / listing flow, not here.
class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  static const String _staticTerms = '''
1. Acceptance of Terms
By using M Auction you agree to these Terms and Conditions. If you do not agree, do not use the service.

2. Eligibility
You must be at least 18 years old and able to form a binding contract. You must complete identity verification (KYC) to list or bid on auctions.

3. Account & Conduct
You are responsible for keeping your account secure. You must not use the platform for any illegal or fraudulent activity. We reserve the right to suspend or terminate accounts that violate these terms.

4. Auctions
Sellers list items accurately. Bidders commit to completing purchases if they win. Deposits may be required to bid. Winners must pay the final price and any applicable fees within the stated period.

5. Fees
Listing fees, buyer/seller commissions, and other fees are as displayed at the time of listing or purchase. By participating you agree to pay all applicable fees.

6. Disputes
Disputes between buyers and sellers should be resolved through our support process. We may mediate but are not liable for user-to-user disputes beyond our stated policies.

7. Limitation of Liability
M Auction is provided "as is." We are not liable for indirect, incidental, or consequential damages arising from your use of the platform.

8. Changes
We may update these terms. Continued use after changes constitutes acceptance. We will notify users of material changes where required.

9. Contact
For questions about these terms, contact us via the Contact Us section in the app.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Terms & Conditions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
        ),
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('content').doc('terms').get(),
        builder: (context, snapshot) {
          String body = _staticTerms;
          if (snapshot.hasData &&
              snapshot.data!.exists &&
              snapshot.data!.data() != null) {
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final text = data?['text'] as String? ?? data?['content'] as String?;
            if (text != null && text.isNotEmpty) body = text;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textPrimary,
                      height: 1.6,
                    ),
              ),
            ),
          );
        },
      ),
    );
  }
}
