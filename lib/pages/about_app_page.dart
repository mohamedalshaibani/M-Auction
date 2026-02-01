import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_theme.dart';

/// About App: overview, how it works, trust/safety, fees. No contact details.
class AboutAppPage extends StatefulWidget {
  const AboutAppPage({super.key});

  @override
  State<AboutAppPage> createState() => _AboutAppPageState();
}

class _AboutAppPageState extends State<AboutAppPage> {
  String _version = '—';
  String _buildNumber = '—';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _version = info.version;
          _buildNumber = info.buildNumber;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'About App',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SizedBox(
                width: 80,
                height: 80,
                child: Image.asset(
                  AppTheme.logoAssetLight,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'M Auction',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Version $_version ($_buildNumber)',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
            ),
            const SizedBox(height: 32),
            _SectionCard(
              title: 'What is M Auction?',
              body: 'M Auction is a premium auction platform for buying and selling luxury and high-value items: watches, bags, art, jewellery, and more. Sellers list items with photos and descriptions; buyers place bids. When an auction ends, the highest bidder wins and completes the purchase securely.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'How it works',
              body: 'Sellers create listings and set a start price and duration. Buyers must complete identity verification (KYC) and may need to add a deposit to bid. When you bid, you commit to buying if you win. After the auction ends, the winner pays the final price and any fees; the platform facilitates the handover. Both parties confirm delivery to release funds.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Trust & safety',
              body: 'We verify seller and buyer identity (KYC). Deposits help ensure serious bidders. Listings are reviewed before going live. Payments and agreements are tracked in-app. Disputes can be raised through our support process. We do not release sensitive contact details until the transaction is confirmed.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Fees',
              body: 'Sellers pay a listing fee when an auction goes live. When an item sells, a commission may apply to the seller and/or buyer; exact amounts are shown at listing and at checkout. Deposits are held until the auction ends and are refunded to non-winners. All applicable fees are displayed before you commit.',
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Our vision',
              body: 'To create a trusted, elegant marketplace where collectors and sellers connect. We focus on transparency, verification, and a seamless experience from listing to delivery.',
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

