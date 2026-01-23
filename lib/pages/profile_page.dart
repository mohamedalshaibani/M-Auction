import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import 'create_profile_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushReplacementNamed('/authGate');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text('Not logged in')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Profile header
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            displayName.isNotEmpty
                                ? displayName[0].toUpperCase()
                                : 'U',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          displayName,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          phoneNumber,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                        if (vipDepositWaived) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.success.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
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
                ),
                
                const SizedBox(height: 20),
                
                // KYC Status Card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              _getKycIcon(kycStatus),
                              color: _getKycColor(kycStatus),
                              size: 24,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Verification Status',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _getKycColor(kycStatus).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: _getKycColor(kycStatus).withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _getKycStatusText(kycStatus),
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: _getKycColor(kycStatus),
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              if (kycStatus == 'not_submitted' || kycStatus == 'rejected')
                                TextButton(
                                  onPressed: () {
                                    Navigator.of(context).pushNamed('/kyc');
                                  },
                                  child: const Text('Start Verification'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Menu items
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.account_balance_wallet_outlined),
                        title: const Text('Wallet'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          // Navigate to wallet tab in MainShell
                          // Since we're in MainShell, we can't directly switch tabs
                          // This is a placeholder - could use a callback or state management
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.list_outlined),
                        title: const Text('My Auctions'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).pushNamed('/sellerMyAuctions');
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.emoji_events_outlined),
                        title: const Text('My Wins'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).pushNamed('/myWins');
                        },
                      ),
                      if (role == 'admin') ...[
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.admin_panel_settings),
                          title: const Text('Admin Panel'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            Navigator.of(context).pushNamed('/adminPanel');
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                
                // Sign out button
                OutlinedButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Sign Out'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
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
