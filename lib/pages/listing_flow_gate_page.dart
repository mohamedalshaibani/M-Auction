import 'package:flutter/material.dart';
import '../services/listing_eligibility_service.dart';
import '../theme/app_theme.dart';
import 'email_verification_page.dart';
import 'listing_terms_accept_page.dart';
import 'sell_create_auction_page.dart';

/// Runs listing eligibility check and redirects to the correct step.
/// Push this when user taps "Create Auction"; it will replace itself with the right screen.
class ListingFlowGatePage extends StatefulWidget {
  const ListingFlowGatePage({super.key});

  @override
  State<ListingFlowGatePage> createState() => _ListingFlowGatePageState();
}

class _ListingFlowGatePageState extends State<ListingFlowGatePage> {
  final _eligibility = ListingEligibilityService();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runGate());
  }

  Future<void> _runGate() async {
    if (!mounted) return;
    setState(() => _error = null);
    final result = await _eligibility.checkEligibility();
    if (!mounted) return;
    switch (result.nextStep) {
      case ListingEligibilityStep.createListing:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const SellCreateAuctionPage()),
        );
        return;
      case ListingEligibilityStep.verifyPhone:
        setState(() => _error = result.message);
        return;
      case ListingEligibilityStep.verifyEmail:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const EmailVerificationPage(),
          ),
        );
        return;
      case ListingEligibilityStep.acceptTerms:
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const ListingTermsAcceptPage()),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Create Auction',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.block, size: 64, color: AppTheme.error),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: AppTheme.textPrimary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Go back'),
                    ),
                  ],
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Checking requirements...',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
