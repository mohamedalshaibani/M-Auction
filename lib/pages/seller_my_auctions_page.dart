import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import '../theme/app_theme.dart';
import 'payment_page.dart';

class SellerMyAuctionsPage extends StatefulWidget {
  const SellerMyAuctionsPage({super.key});

  @override
  State<SellerMyAuctionsPage> createState() => _SellerMyAuctionsPageState();
}

class _SellerMyAuctionsPageState extends State<SellerMyAuctionsPage> {
  final AuctionService _auctionService = AuctionService();
  String? _submittingAuctionId;

  static String _statusLabel(String state) {
    switch (state) {
      case 'DRAFT':
        return 'Draft';
      case 'PENDING_APPROVAL':
        return 'Pending approval';
      case 'APPROVED_AWAITING_PAYMENT':
        return 'Awaiting payment';
      case 'ACTIVE':
        return 'Active';
      case 'ENDED':
      case 'ENDED_NO_RESPONSE':
        return 'Ended';
      default:
        return state;
    }
  }

  static Color _statusColor(String state) {
    switch (state) {
      case 'DRAFT':
        return AppTheme.textSecondary;
      case 'PENDING_APPROVAL':
        return AppTheme.warning;
      case 'APPROVED_AWAITING_PAYMENT':
        return AppTheme.primaryBlue;
      case 'ACTIVE':
        return AppTheme.success;
      case 'ENDED':
      case 'ENDED_NO_RESPONSE':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  void _payListingFee(String auctionId, double amount) {
    Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PaymentPage(
          type: 'listing_fee',
          amount: amount,
          auctionId: auctionId,
          title: 'Pay Listing Fee',
        ),
      ),
    ).then((success) {
      if (!mounted) return;
      if (success == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Listing fee paid. Auction will be activated.'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    });
  }

  Future<void> _submitForApproval(String auctionId) async {
    setState(() => _submittingAuctionId = auctionId);
    
    try {
      await _auctionService.submitForApproval(auctionId);
      
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Auction submitted for admin approval'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: AppTheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _submittingAuctionId = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.login, size: 64, color: AppTheme.textTertiary),
              const SizedBox(height: 16),
              Text(
                'Not logged in',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Please log in to view your auctions',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Auctions'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _auctionService.streamSellerAuctions(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: AppTheme.error),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading auctions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: AppTheme.textTertiary),
                  const SizedBox(height: 16),
                  Text(
                    'No auctions yet',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create your first auction to get started',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
            );
          }

          // Sort by createdAt (descending - newest first)
          final sortedDocs = List<QueryDocumentSnapshot>.from(
            snapshot.data!.docs,
          )..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTimestamp = aData['createdAt'] as Timestamp?;
              final bTimestamp = bData['createdAt'] as Timestamp?;

              if (aTimestamp == null && bTimestamp == null) return 0;
              if (aTimestamp == null) return 1;
              if (bTimestamp == null) return -1;

              return bTimestamp.compareTo(aTimestamp); // Descending
            });

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final auctionId = doc.id;

              final title = data['title'] as String? ?? 'Untitled';
              final state = data['state'] as String? ?? 'UNKNOWN';
              final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;

              final statusLabel = _statusLabel(state);
              final statusColor = _statusColor(state);

              final listingFeeAmount = (data['listingFeeAmount'] as num?)?.toDouble();
              final listingFeePaid = data['listingFeePaid'] as bool? ?? false;
              final needsPayment = state == 'APPROVED_AWAITING_PAYMENT' && !listingFeePaid && listingFeeAmount != null;
              final isDraft = state == 'DRAFT';
              final isSubmitting = _submittingAuctionId == auctionId;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppTheme.border, width: 1),
                  ),
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    onTap: () {
                      Navigator.of(context).pushNamed(
                        '/auctionDetail?auctionId=$auctionId',
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: 0.15,
                                ),
                          ),
                          const SizedBox(height: 8),
                          // Status + price row
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusLabel,
                                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                        color: statusColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                'AED ${currentPrice.toStringAsFixed(0)}',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: AppTheme.textSecondary,
                                      fontWeight: FontWeight.w500,
                                    ),
                              ),
                            ],
                          ),
                          // Action row (compact)
                          if (isDraft || needsPayment) ...[
                            const SizedBox(height: 12),
                            const Divider(height: 1),
                            const SizedBox(height: 12),
                            if (isDraft)
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Add images and required fields, then submit.',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: AppTheme.textSecondary,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  isSubmitting
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        )
                                      : TextButton.icon(
                                          onPressed: () => _submitForApproval(auctionId),
                                          icon: const Icon(Icons.send_rounded, size: 16),
                                          label: const Text('Submit for approval'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: AppTheme.primaryBlue,
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                        ),
                                ],
                              ),
                            if (needsPayment)
                              Row(
                                children: [
                                  Text(
                                    'Listing fee AED ${listingFeeAmount!.toStringAsFixed(2)}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: AppTheme.textSecondary,
                                        ),
                                  ),
                                  const SizedBox(width: 12),
                                  TextButton(
                                    onPressed: () => _payListingFee(auctionId, listingFeeAmount),
                                    child: const Text('Pay fee'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppTheme.success,
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
