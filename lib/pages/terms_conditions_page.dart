import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

/// Terms & Conditions: from Firestore content/terms or static fallback.
/// Agreement step exists only during auction creation / listing flow, not here.
class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  /// Static fallback text; also used by listing flow terms acceptance.
  static const String staticTerms = '''
1. Acceptance of Terms
By accessing or using M Auction ("the Platform," "we," "us," or "our"), you agree to be bound by these Terms and Conditions. If you do not agree to these terms, you must not use the service. These terms apply to all users of the M Auction mobile applications and related services, including use on Apple iOS and Google Android.

2. Eligibility
You must be at least 18 years old and legally capable of entering into binding contracts in your jurisdiction. You must complete identity verification (KYC) where required to list items or place bids. You are responsible for ensuring your use of the Platform complies with all applicable local laws.

3. Nature of the Platform — Marketplace Only
M Auction is a marketplace that connects buyers and sellers. We do not sell, own, or take custody of any products listed on the Platform. All listings are created by users (sellers). Buyers place bids at their own discretion. The Platform provides technology and services to facilitate auctions and to record transactions between users. We are not a party to any sale or purchase between users.
The Platform does not provide escrow, custody, storage, shipping, or any payment guarantee. All inspections, payments, and handovers are arranged directly between buyer and seller unless explicitly stated otherwise.

4. User Responsibility — Sellers and Buyers
The seller and the buyer are solely and fully responsible for:
• Verifying the item, its condition, authenticity, and specifications before or after a transaction.
• Agreeing between themselves on inspection, handover, payment, and any legal terms of the sale.
• Complying with all applicable laws relating to the sale, purchase, and transfer of items.
The buyer is solely responsible for inspecting or verifying the item (in person or via any agreed third party) before completing any transaction. The Platform is not responsible for any mismatch between photos, descriptions, authenticity, or condition.
The Platform's role is limited to facilitating the auction process and creating a transaction record between the parties. Once the auction has ended and the transaction record is created, the Platform's facilitation role in respect of that transaction is complete. Any further arrangements (including inspection, payment, delivery, and legal obligations) are solely between the buyer and the seller.

5. No Professional Advice
The Platform does not provide legal, financial, or other professional advice. Users should seek independent advice if needed before entering any transaction.

6. No Liability — Transactions at Your Risk
To the fullest extent permitted by law:
• The Platform is not responsible for the quality, authenticity, condition, legality, or accuracy of any product or listing. Listings are created by users; we do not verify or guarantee any item.
• The Platform is not liable for any losses, disputes, damages, or claims arising between users or from any transaction conducted through the Platform.
• All transactions are conducted at the users' own risk. Users must conduct their own due diligence and rely on their own judgment.

7. Fraud, Misuse, and Enforcement
The Platform may monitor activity to detect fraud, scams, or other misuse. If fraud, scam, or illegal activity is suspected or confirmed, the Platform may suspend or permanently terminate user accounts, freeze or cancel auctions or transactions, and take any other protective action we deem necessary, without prior notice where we reasonably believe it is required. Users must not use the Platform for any illegal or fraudulent purpose. You are responsible for keeping your account secure and for all activity under your account.

8. Data Disclosure — Legal Compliance and Protection
In cases of confirmed or suspected fraud, illegal activity, or when required by law, the Platform may share relevant user information with the affected party and/or official authorities (including law enforcement and regulators) when legally required or when necessary to protect users and the Platform. Such disclosure is limited to what is reasonably necessary for investigation, legal compliance, dispute support, and protection of users and the Platform.

9. Separation of Roles — Disputes Between Users
The Platform facilitates data exchange and auction flow only. We are not a party to any contract of sale between buyer and seller. Any legal claims, disputes, or recovery actions (including but not limited to refunds, damages, or enforcement of sale terms) are matters to be handled directly between the buyer and the seller. Users may use our support channels for assistance where we offer it, but we have no obligation to resolve user-to-user disputes and are not liable for their outcome.

10. Fees
Listing fees, buyer and seller commissions, and other fees are displayed at the time of listing or purchase. By participating in the Platform you agree to pay all applicable fees in accordance with the then-current pricing and policies.

11. Limitation of Liability
To the maximum extent permitted by applicable law, M Auction and its affiliates, officers, directors, employees, and agents shall not be liable for any indirect, incidental, special, consequential, or punitive damages, or for any loss of profits, data, or goodwill, arising from or in connection with your use of the Platform or any transaction between users. Our total liability in respect of any claim arising from these terms or your use of the Platform shall not exceed the amount of fees paid by you to us in the twelve (12) months preceding the claim. The Platform is provided "as is" and "as available" without warranties of any kind, except where such disclaimers are prohibited by law.

12. Governing Law and Jurisdiction
These Terms and Conditions are governed by the laws of the United Arab Emirates. Any dispute arising in connection with these terms or the Platform shall be subject to the exclusive jurisdiction of the courts of the United Arab Emirates, unless otherwise required by mandatory law.

13. Changes to These Terms
We may update these Terms and Conditions from time to time. We will notify users of material changes where required by law or by app store guidelines. Continued use of the Platform after changes take effect constitutes acceptance of the revised terms. If you do not agree to updated terms, you must stop using the Platform.

14. Contact
For questions about these Terms and Conditions, please contact us via the Contact Us section in the app or through the contact details provided in the app listing.
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'Terms & Conditions'),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('content').doc('terms').get(),
        builder: (context, snapshot) {
          String body = staticTerms;
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
