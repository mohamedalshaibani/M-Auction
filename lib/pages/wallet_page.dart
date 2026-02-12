import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_service.dart';
import '../services/admin_settings_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/guest_sign_in_prompt.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/admin_support_badge.dart';
import '../services/payment_service.dart';
import 'payment_page.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key, this.returnAuctionId, this.onNotNow});

  final String? returnAuctionId;
  /// When in MainShell as guest, called when user taps "Not now" (switch to Home).
  final VoidCallback? onNotNow;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final FirestoreService _firestoreService = FirestoreService();
  final AdminSettingsService _adminSettings = AdminSettingsService();
  final PaymentService _paymentService = PaymentService();
  bool _infoExpanded = false;
  bool _withdrawing = false;

  static const List<double> _fallbackDepositAmounts = [50, 100, 200, 500];

  Future<void> _showAddDepositOptions() async {
    final tiers = await _adminSettings.getDepositTiersList();
    final maxCap = await _adminSettings.getDepositMaxAmount();
    final tierAmounts = tiers.isNotEmpty
        ? (tiers.map((t) => (t['amount'] as num).toDouble()).toList()..sort())
        : _fallbackDepositAmounts;
    final allowedAmounts = maxCap.isFinite && maxCap > 0
        ? tierAmounts.where((a) => a <= maxCap).toList()
        : tierAmounts;
    if (allowedAmounts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No deposit tiers within max cap. Contact support.'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
      return;
    }

    double? selectedAmount;
    double? selectedMaxBid;

    if (!mounted) return;
    final amount = await showModalBottomSheet<double?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            void pickAmount(double amount) {
              if (maxCap.isFinite && maxCap > 0 && amount > maxCap) return;
              setModalState(() {
                selectedAmount = amount;
                selectedMaxBid = null;
              });
              _adminSettings.getMaxBidLimitForDepositAmount(amount).then((maxBid) {
                if (context.mounted) setModalState(() => selectedMaxBid = maxBid);
              });
            }
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Add Deposit',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Choose amount (AED). Amount must be > 0${maxCap.isFinite && maxCap > 0 ? ' and ≤ ${maxCap.toStringAsFixed(0)}' : ''}.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: allowedAmounts.map((amount) {
                        final isSelected = selectedAmount == amount;
                        return FilterChip(
                          label: Text('AED ${amount.toInt()}'),
                          labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                          selected: isSelected,
                          onSelected: (_) => pickAmount(amount),
                        );
                      }).toList(),
                    ),
                    if (selectedAmount != null && selectedMaxBid != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          'This deposit allows you to bid up to AED ${formatMoney(selectedMaxBid!)}.',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel'),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: selectedAmount != null && selectedAmount! > 0
                              ? () => Navigator.pop(context, selectedAmount!)
                              : null,
                          child: const Text('Continue to payment'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (amount != null && amount > 0 && mounted) {
      if (maxCap.isFinite && maxCap > 0 && amount > maxCap) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Amount must not exceed AED ${formatMoney(maxCap)}'),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
      Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (context) => PaymentPage(
            type: 'deposit',
            amount: amount,
            title: 'Add Deposit',
          ),
        ),
      ).then((success) {
        if (success == true && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Deposit added successfully'),
              backgroundColor: AppTheme.success,
            ),
          );
        }
      });
    }
  }

  Future<void> _requestWithdraw() async {
    setState(() => _withdrawing = true);
    try {
      await _paymentService.requestDepositWithdraw();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Withdrawal requested. Funds will be refunded shortly.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Withdraw failed: $e'),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
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
      case 'reserved_for_bid':
      case 'reserved_for_win':
        return AppTheme.primaryBlue;
      case 'waived':
        return AppTheme.success;
      case 'insufficient':
        return AppTheme.warning;
      case 'forfeited':
      case 'in_dispute':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  String _getDepositStatusText(String status) {
    switch (status) {
      case 'held':
        return 'Held';
      case 'reserved_for_bid':
        return 'Reserved (bid)';
      case 'reserved_for_win':
        return 'Reserved (win)';
      case 'waived':
        return 'Waived (VIP)';
      case 'insufficient':
        return 'Insufficient';
      case 'forfeited':
        return 'Forfeited';
      case 'in_dispute':
        return 'In dispute';
      default:
        return 'None';
    }
  }

  Widget _buildInfoItem(BuildContext context, String title, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSecondary,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.backgroundLight,
        appBar: UnifiedAppBar(
          title: 'Wallet',
          leading: widget.returnAuctionId != null
              ? IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                )
              : null,
          actions: const [AdminSupportBadge()],
        ),
        body: GuestSignInPrompt(
          title: 'Wallet',
          icon: Icons.account_balance_wallet_outlined,
          returnAuctionId: widget.returnAuctionId,
          onNotNow: widget.onNotNow,
          onContinue: () {
            final args = widget.returnAuctionId != null
                ? <String, dynamic>{'returnAuctionId': widget.returnAuctionId}
                : null;
            Navigator.of(context).pushNamed('/login', arguments: args);
          },
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: UnifiedAppBar(
        title: 'Wallet',
        leading: widget.returnAuctionId != null
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: const [AdminSupportBadge()],
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
          final reservedDeposit =
              (data?['reservedDeposit'] as num?)?.toDouble() ?? 0.0;
          final depositStatus = data?['depositStatus'] as String? ?? 'none';
          final depositRefs =
              (data?['depositRefs'] is List) ? (data?['depositRefs'] as List) : const <dynamic>[];
          final hasDepositRefs = depositRefs.isNotEmpty;
          final eligibleDeposit = (availableDeposit - reservedDeposit).clamp(0.0, double.infinity);
          final refundable =
              (availableDeposit - reservedDeposit).clamp(0.0, double.infinity);

          final canWithdraw = refundable > 0 &&
              reservedDeposit == 0 &&
              hasDepositRefs &&
              depositStatus != 'in_dispute';

          String? withdrawBlockedReason() {
            if (refundable <= 0) return 'No refundable deposit available.';
            if (reservedDeposit > 0) {
              return 'Deposit is reserved for an active bid or a won auction.';
            }
            if (depositStatus == 'in_dispute') {
              return 'Withdrawals are disabled while your deposit is in dispute.';
            }
            if (!hasDepositRefs) {
              return 'This deposit can’t be refunded in-app (missing payment reference). Please contact support.';
            }
            return null;
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Deposit summary
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bidding Security Deposit',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Refundable guarantee required to place bids',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              'AED ${formatMoney(availableDeposit)}',
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: availableDeposit > 0 ? AppTheme.success : AppTheme.textSecondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
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
                        if (availableDeposit <= 0)
                          Text(
                            'No active deposit. Add a deposit to start bidding.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontStyle: FontStyle.italic,
                                ),
                          )
                        else if (eligibleDeposit <= 0)
                          Text(
                            'Your deposit is reserved for active bids.',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          )
                        else
                          FutureBuilder<double>(
                            future: _adminSettings.calculateMaxBidLimit(eligibleDeposit),
                            builder: (context, bidLimitSnap) {
                              final bidLimit = bidLimitSnap.data ?? 0.0;
                              if (bidLimitSnap.hasError || bidLimit <= 0) {
                                return Text(
                                  'Your deposit allows you to participate in auctions.',
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: AppTheme.textSecondary,
                                      ),
                                );
                              }
                              final limitText = bidLimit.isFinite
                                  ? 'AED ${formatMoney(bidLimit)}'
                                  : 'unlimited';
                              return Text(
                                'Your current deposit allows you to bid up to $limitText.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. Actions
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _showAddDepositOptions,
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
                        if (availableDeposit > 0) ...[
                          const SizedBox(height: 12),
                          if (canWithdraw)
                            OutlinedButton.icon(
                              onPressed: _withdrawing ? null : _requestWithdraw,
                              icon: _withdrawing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child:
                                          CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.account_balance_wallet),
                              label: Text(
                                _withdrawing ? 'Withdrawing...' : 'Withdraw deposit',
                              ),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                foregroundColor: AppTheme.primaryBlue,
                              ),
                            )
                          else ...[
                            OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.account_balance_wallet),
                              label: const Text('Withdraw deposit'),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                foregroundColor: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              withdrawBlockedReason() ??
                                  'Withdraw is currently unavailable.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 3. Explanation / info
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: () => setState(() => _infoExpanded = !_infoExpanded),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Icon(
                                Icons.help_outline,
                                size: 24,
                                color: AppTheme.primaryBlue,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'How deposits work',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                              ),
                              Icon(
                                _infoExpanded ? Icons.expand_less : Icons.expand_more,
                                color: AppTheme.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_infoExpanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildInfoItem(
                                context,
                                'When is a deposit required?',
                                'A deposit is required to place bids on auctions. It ensures serious participation.',
                              ),
                              const SizedBox(height: 16),
                              _buildInfoItem(
                                context,
                                'How is it held?',
                                'When you bid, a portion of your deposit may be reserved. It stays in your wallet until the auction ends.',
                              ),
                              const SizedBox(height: 16),
                              _buildInfoItem(
                                context,
                                'When is it released or forfeited?',
                                'Non-winners: your deposit is released immediately. Winners: it\'s held until purchase is confirmed. If you don\'t complete the purchase by the deadline, the deposit may be forfeited.',
                              ),
                            ],
                          ),
                        ),
                    ],
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
