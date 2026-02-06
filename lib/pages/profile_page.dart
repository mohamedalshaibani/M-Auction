import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/guest_sign_in_prompt.dart';
import '../widgets/header_logo.dart';
import '../widgets/unified_app_bar.dart';
import 'create_profile_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.onNotNow});

  /// When in MainShell as guest, called when user taps "Not now" (switch to Home).
  final VoidCallback? onNotNow;

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: const UnifiedAppBar(title: 'Profile'),
        body: GuestSignInPrompt(
          title: 'Profile',
          icon: Icons.person_outline,
          onNotNow: onNotNow,
          onContinue: () => Navigator.of(context).pushNamed('/login'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: UnifiedAppBar(
        titleWidget: Row(
          children: [
            const HeaderLogo(),
            const SizedBox(width: 12),
            Text(
              'Profile',
              style: Theme.of(context).appBarTheme.titleTextStyle?.copyWith(
                    color: Theme.of(context).appBarTheme.foregroundColor ?? AppTheme.textPrimary,
                  ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 48,
                      color: AppTheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading profile',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.error,
                          ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        // Retry by rebuilding
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Check if user document exists
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 64,
                      color: AppTheme.textTertiary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Profile missing',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Please complete setup',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const CreateProfilePage(),
                          ),
                        );
                      },
                      child: const Text('Complete Setup'),
                    ),
                  ],
                ),
              ),
            );
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final displayName = userData?['displayName'] as String? ?? 'User';
          final phoneNumber = user.phoneNumber ?? userData?['phoneNumber'] as String? ?? 'Not available';
          final kycStatus = userData?['kycStatus'] as String? ?? 'not_submitted';
          final role = userData?['role'] as String?;
          final vipDepositWaived = userData?['vipDepositWaived'] as bool? ?? false;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile header card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                        child: Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : 'U',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phoneNumber,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                            if (vipDepositWaived) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'VIP Member',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: AppTheme.success,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Verification section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _getKycIcon(kycStatus),
                            color: _getKycColor(kycStatus),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Verification',
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _getKycColor(kycStatus).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _getKycColor(kycStatus).withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _getKycStatusText(kycStatus),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _getKycColor(kycStatus),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                            if (kycStatus == 'not_submitted' || kycStatus == 'rejected')
                              TextButton(
                                onPressed: () => Navigator.of(context).pushNamed('/kyc'),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Text(
                                  'Verify',
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: AppTheme.primaryBlue,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Quick links
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Column(
                    children: [
                      _ProfileMenuItem(
                        icon: Icons.account_balance_wallet_outlined,
                        label: 'Wallet',
                        onTap: () {},
                      ),
                      const Divider(height: 1),
                      _ProfileMenuItem(
                        icon: Icons.list_outlined,
                        label: 'My Auctions',
                        onTap: () => Navigator.of(context).pushNamed('/sellerMyAuctions'),
                      ),
                      const Divider(height: 1),
                      _ProfileMenuItem(
                        icon: Icons.emoji_events_outlined,
                        label: 'My Wins',
                        onTap: () => Navigator.of(context).pushNamed('/myWins'),
                      ),
                      if (role == 'admin') ...[
                        const Divider(height: 1),
                        _ProfileMenuItem(
                          icon: Icons.admin_panel_settings_outlined,
                          label: 'Admin Panel',
                          onTap: () => Navigator.of(context).pushNamed('/adminPanel'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout, size: 20),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppTheme.border),
                    foregroundColor: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  IconData _getKycIcon(String status) {
    switch (status) {
      case 'approved':
        return Icons.check_circle;
      case 'pending':
      case 'submitted':
        return Icons.pending;
      case 'rejected':
        return Icons.error;
      default:
        return Icons.info_outline;
    }
  }

  Color _getKycColor(String status) {
    switch (status) {
      case 'approved':
        return AppTheme.success;
      case 'pending':
      case 'submitted':
        return AppTheme.warning;
      case 'rejected':
        return AppTheme.error;
      default:
        return AppTheme.info;
    }
  }

  String _getKycStatusText(String status) {
    switch (status) {
      case 'approved':
        return 'Verified';
      case 'pending':
      case 'submitted':
        return 'Under Review';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Not Verified';
    }
  }
}

class _ProfileMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, size: 22, color: AppTheme.textSecondary),
      title: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
      ),
      trailing: Icon(Icons.chevron_right, size: 20, color: AppTheme.textTertiary),
      onTap: onTap,
    );
  }
}
