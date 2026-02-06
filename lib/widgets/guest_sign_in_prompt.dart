import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared guest-state UI for Wallet, Profile, and bidding/listing.
/// [title] e.g. 'Wallet'; [onContinue] typically push /login; [onNotNow] pop or switch to Home.
class GuestSignInPrompt extends StatelessWidget {
  const GuestSignInPrompt({
    super.key,
    required this.title,
    required this.icon,
    this.returnAuctionId,
    this.onNotNow,
    required this.onContinue,
  });

  final String title;
  final IconData icon;
  final String? returnAuctionId;
  final VoidCallback? onNotNow;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: AppTheme.textTertiary),
            const SizedBox(height: 20),
            Text(
              'Sign in or Create an account',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'To access Wallet, Profile, and bidding features.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
              child: const Text('Continue with Phone (Sign in / Sign up)'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () {
                if (returnAuctionId != null) {
                  Navigator.of(context).pop();
                } else {
                  onNotNow?.call();
                }
              },
              child: const Text('Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
