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
  bool _isSubmitting = false;

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
    setState(() => _isSubmitting = true);
    
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
        setState(() => _isSubmitting = false);
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
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final auctionId = doc.id;

              final title = data['title'] as String? ?? 'Untitled';
              final state = data['state'] as String? ?? 'UNKNOWN';
              final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;

              Color stateColor = AppTheme.textSecondary;
              switch (state) {
                case 'DRAFT':
                  stateColor = AppTheme.textSecondary;
                  break;
                case 'PENDING_APPROVAL':
                  stateColor = AppTheme.warning;
                  break;
                case 'APPROVED_AWAITING_PAYMENT':
                  stateColor = AppTheme.primaryBlue;
                  break;
                case 'ACTIVE':
                  stateColor = AppTheme.success;
                  break;
                case 'ENDED':
                  stateColor = AppTheme.error;
                  break;
              }

              final listingFeeAmount = (data['listingFeeAmount'] as num?)?.toDouble();
              final listingFeePaid = data['listingFeePaid'] as bool? ?? false;
              final needsPayment = state == 'APPROVED_AWAITING_PAYMENT' && !listingFeePaid && listingFeeAmount != null;
              final isDraft = state == 'DRAFT';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Text(
                        'State: $state',
                        style: TextStyle(
                          color: stateColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Current: ${currentPrice.toStringAsFixed(2)}'),
                      if (isDraft) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.primaryBlue),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Ready to submit?',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Make sure you\'ve added images and filled all required fields.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _isSubmitting ? null : () => _submitForApproval(auctionId),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.primaryBlue,
                                  ),
                                  icon: _isSubmitting 
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                          ),
                                        )
                                      : const Icon(Icons.send),
                                  label: Text(_isSubmitting ? 'Submitting...' : 'Submit for Approval'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (needsPayment) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.warning.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.warning),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Listing Fee: AED ${listingFeeAmount.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _payListingFee(auctionId, listingFeeAmount),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.success,
                                  ),
                                  child: const Text('Pay Listing Fee'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      '/auctionDetail?auctionId=$auctionId',
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
