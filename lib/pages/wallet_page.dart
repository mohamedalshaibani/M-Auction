import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final FirestoreService _firestoreService = FirestoreService();

  void _showAddDepositModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.info_outline,
              size: 48,
              color: AppTheme.primaryBlue,
            ),
            const SizedBox(height: 16),
            Text(
              'Payments Available on Web',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Mobile payment integration is coming soon. Please use the web version to add deposits.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }

  void _showDepositRules() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deposit Rules'),
        content: const SingleChildScrollView(
          child: Text(
            '• Deposits are required to participate in auctions\n'
            '• Minimum deposit amount varies by auction\n'
            '• Deposits are held until auction ends\n'
            '• Winners: deposit is held until purchase is confirmed\n'
            '• Non-winners: deposit is released immediately\n'
            '• VIP members may have deposit requirements waived',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Color _getDepositStatusColor(String status) {
    switch (status) {
      case 'held':
        return AppTheme.primaryBlue;
      case 'waived':
        return AppTheme.success;
      case 'insufficient':
        return AppTheme.warning;
      case 'forfeited':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _getDepositStatusText(String status) {
    switch (status) {
      case 'held':
        return 'Held';
      case 'waived':
        return 'Waived (VIP)';
      case 'insufficient':
        return 'Insufficient';
      case 'forfeited':
        return 'Forfeited';
      default:
        return 'None';
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
        title: const Text('Wallet'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestoreService.streamWallet(user.uid),
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
                      'Error loading wallet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.error,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${snapshot.error}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {});
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

          // Check if wallet document exists
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      size: 64,
                      color: AppTheme.textTertiary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Wallet not set up yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {});
                      },
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>?;
          final availableDeposit =
              (data?['availableDeposit'] as num?)?.toDouble() ?? 0.0;
          final depositStatus = data?['depositStatus'] as String? ?? 'none';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Premium wallet header card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Available Deposit',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                            // Deposit status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _getDepositStatusColor(depositStatus).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _getDepositStatusColor(depositStatus).withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Text(
                                _getDepositStatusText(depositStatus),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: _getDepositStatusColor(depositStatus),
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'AED ${availableDeposit.toStringAsFixed(2)}',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                color: AppTheme.success,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // Actions
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _showAddDepositModal,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Deposit'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _showDepositRules,
                          icon: const Icon(Icons.info_outline),
                          label: const Text('Deposit Rules'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
