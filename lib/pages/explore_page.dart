import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';
import '../theme/app_theme.dart';

class ExplorePage extends StatelessWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auctionService = AuctionService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore'),
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
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pushNamed(
                      '/auctionDetail?auctionId=$auctionId',
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Image placeholder
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundGrey,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.image_outlined,
                            color: AppTheme.textTertiary,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 16),
                        // Content
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                brand,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.textSecondary,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text(
                                    'AED ${currentPrice.toStringAsFixed(0)}',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          color: AppTheme.primaryBlue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 14,
                                        color: AppTheme.textSecondary,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        timeLeft,
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              color: AppTheme.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
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
