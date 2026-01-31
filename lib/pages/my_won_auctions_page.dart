import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/auction_service.dart';

class MyWonAuctionsPage extends StatelessWidget {
  const MyWonAuctionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final auctionService = AuctionService();

    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Wins')),
        body: const Center(child: Text('Please log in to view your won auctions')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Wins'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: auctionService.streamWonAuctions(user.uid),
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
              child: Text('No won auctions yet'),
            );
          }

          // Sort by endsAt (descending - most recent first)
          final sortedDocs = List<QueryDocumentSnapshot>.from(
            snapshot.data!.docs,
          )..sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aEndsAt = aData['endsAt'] as Timestamp?;
              final bEndsAt = bData['endsAt'] as Timestamp?;

              if (aEndsAt == null && bEndsAt == null) return 0;
              if (aEndsAt == null) return 1;
              if (bEndsAt == null) return -1;

              return bEndsAt.compareTo(aEndsAt); // Descending
            });

          return ListView.builder(
            itemCount: sortedDocs.length,
            itemBuilder: (context, index) {
              final doc = sortedDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final auctionId = doc.id;

              final title = data['title'] as String? ?? 'Untitled';
              final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
              final state = data['state'] as String? ?? 'UNKNOWN';
              final endsAt = data['endsAt'] as Timestamp?;

              String stateText = state;
              Color stateColor = Colors.grey;
              if (state == 'ENDED') {
                stateText = 'Ended';
                stateColor = Colors.red;
              } else if (state == 'ACTIVE') {
                stateText = 'Active';
                stateColor = Colors.green;
              }

              String endsAtText = 'N/A';
              if (endsAt != null) {
                final endDate = endsAt.toDate();
                endsAtText = '${endDate.year}-${endDate.month.toString().padLeft(2, '0')}-${endDate.day.toString().padLeft(2, '0')}';
              }

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(title),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Price: AED ${currentPrice.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('State: '),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: stateColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: stateColor),
                            ),
                            child: Text(
                              stateText,
                              style: TextStyle(
                                color: stateColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('Ended: $endsAtText'),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
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
