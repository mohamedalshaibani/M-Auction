import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import 'payment_page.dart';

class SellerMyAuctionsPage extends StatefulWidget {
  const SellerMyAuctionsPage({super.key});

  @override
  State<SellerMyAuctionsPage> createState() => _SellerMyAuctionsPageState();
}

class _SellerMyAuctionsPageState extends State<SellerMyAuctionsPage> {
  final AuctionService _auctionService = AuctionService();

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
            backgroundColor: Colors.green,
          ),
        );
      }
    });
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
        title: const Text('My Auctions'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _auctionService.streamSellerAuctions(user.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text('Error: ${snapshot.error}'),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text('No auctions found'),
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

              Color stateColor = Colors.grey;
              switch (state) {
                case 'DRAFT':
                  stateColor = Colors.grey;
                  break;
                case 'PENDING_APPROVAL':
                  stateColor = Colors.orange;
                  break;
                case 'APPROVED_AWAITING_PAYMENT':
                  stateColor = Colors.blue;
                  break;
                case 'ACTIVE':
                  stateColor = Colors.green;
                  break;
                case 'ENDED':
                  stateColor = Colors.red;
                  break;
              }

              final listingFeeAmount = (data['listingFeeAmount'] as num?)?.toDouble();
              final listingFeePaid = data['listingFeePaid'] as bool? ?? false;
              final needsPayment = state == 'APPROVED_AWAITING_PAYMENT' && !listingFeePaid && listingFeeAmount != null;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'State: $state',
                        style: TextStyle(
                          color: stateColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('Current: ${currentPrice.toStringAsFixed(2)}'),
                      if (needsPayment) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Listing Fee: AED ${listingFeeAmount.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => _payListingFee(auctionId, listingFeeAmount),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
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
