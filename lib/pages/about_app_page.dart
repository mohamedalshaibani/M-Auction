import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

/// About App: overview, how it works, trust/safety, fees. No contact details.
class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'About App'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox(
                width: 120,
                height: 120,
                child: Image.asset(
                  AppTheme.logoAssetLight,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 32),
            _SectionCard(
              title: 'What is M Auction?',
              body: 'M Auction is a digital marketplace platform that facilitates the listing and discovery of items offered for sale by its users through an auction-based system.\n'
                  'M Auction does not sell, own, inspect, store, ship, or purchase any items displayed on the platform.\n\n'
                  'All items are listed by independent sellers, and all bids are placed by independent buyers.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Platform Role & Responsibility',
              body: 'M Auction acts solely as a neutral intermediary that enables:\n'
                  '• Display of item listings and related information\n'
                  '• Auction bidding between users\n'
                  '• Transmission of sale-related data between sellers and buyers\n'
                  '• Creation of an in-app digital record of the transaction\n\n'
                  'M Auction is not a party to the sale contract between the seller and the buyer.\n\n'
                  'The platform\'s role and responsibility end once the transaction record is created and the parties are connected.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Buyer & Seller Responsibility',
              body: 'Buyers and sellers are fully and solely responsible for:\n'
                  '• Verifying the authenticity, condition, and specifications of any item\n'
                  '• Agreeing on inspection, delivery, handover, and payment methods\n'
                  '• Ensuring receipt of the item and/or funds\n'
                  '• Complying with all applicable laws governing private sales and contracts\n\n'
                  'M Auction does not guarantee:\n'
                  '• Item quality or authenticity\n'
                  '• Accuracy of descriptions or images\n'
                  '• Successful delivery or payment\n'
                  '• Fulfillment of obligations by either party',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Verification, Security & Fraud Prevention',
              body: 'The platform may require users to complete verification steps such as:\n'
                  '• Phone number verification\n'
                  '• Email verification\n'
                  '• Identity verification (KYC)\n'
                  '• Deposits or guarantees\n\n'
                  'These measures are implemented to reduce fraud and improve platform safety, but they do not constitute a warranty or assumption of liability by M Auction.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Fraud, Misuse & Legal Cooperation',
              body: 'If fraud, deception, misuse, or suspicious activity is suspected or confirmed:\n'
                  '• M Auction reserves the right to suspend or terminate the transaction\n'
                  '• Restrict or permanently ban the involved account(s)\n'
                  '• Share relevant user data with the affected party and/or official authorities, where legally permitted or required',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Limitation of Liability',
              body: 'M Auction provides its services "as is" and shall not be liable for:\n'
                  '• Any losses, damages, or disputes arising between users\n'
                  '• Any indirect, incidental, or consequential damages\n'
                  '• Any failure by users to fulfill their obligations\n\n'
                  'By using the platform, users acknowledge and accept that all transactions are conducted at their own risk.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Our Vision',
              body: 'Our vision is to build a transparent and secure digital marketplace that connects buyers and sellers while maintaining clear boundaries of responsibility, compliance with platform policies, and cooperation with applicable laws.',
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String body;

  const _SectionCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

