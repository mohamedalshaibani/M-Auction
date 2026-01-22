import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import 'auction_detail_page.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auctionService = AuctionService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore Auctions'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: auctionService.streamActiveAuctions(),
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
              child: Text('No active auctions available'),
            );
          }

          // Sort by endsAt (ascending - ending soonest first)
          final sortedDocs = List<QueryDocumentSnapshot>.from(
            snapshot.data!.docs,
          )..sort((a, b) {
              final aEndsAt = a.data() as Map<String, dynamic>;
              final bEndsAt = b.data() as Map<String, dynamic>;
              final aTimestamp = aEndsAt['endsAt'] as Timestamp?;
              final bTimestamp = bEndsAt['endsAt'] as Timestamp?;

              if (aTimestamp == null && bTimestamp == null) return 0;
              if (aTimestamp == null) return 1;
              if (bTimestamp == null) return -1;

              return aTimestamp.compareTo(bTimestamp);
            });

          return ListView.builder(
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final auctionId = doc.id;

              final title = data['title'] as String? ?? 'Untitled';
              final brand = data['brand'] as String? ?? 'Unknown';
              final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
              final endsAt = data['endsAt'] as Timestamp?;

              String timeLeft = 'Ended';
              if (endsAt != null) {
                final now = DateTime.now();
                final endDate = endsAt.toDate();
                final difference = endDate.difference(now);

                if (difference.isNegative) {
                  timeLeft = 'Ended';
                } else if (difference.inDays > 0) {
                  timeLeft = '${difference.inDays}d ${difference.inHours % 24}h';
                } else if (difference.inHours > 0) {
                  timeLeft = '${difference.inHours}h ${difference.inMinutes % 60}m';
                } else {
                  timeLeft = '${difference.inMinutes}m';
                }
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Brand: $brand'),
                      const SizedBox(height: 4),
                      Text(
                        'Current: ${currentPrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Time left: $timeLeft'),
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
