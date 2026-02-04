import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

/// Static FAQ entries (used when Firestore is empty or fails).
final List<Map<String, String>> _staticFaq = [
  {'question': 'What is M Auction?', 'answer': 'M Auction is a premium auction platform for luxury and high-value items. Sellers list items; buyers place bids. The highest bidder when the auction ends wins and completes the purchase.'},
  {'question': 'Do I need to verify my identity?', 'answer': 'Yes. Identity verification (KYC) is required to list items or place bids. This helps keep the platform safe for everyone.'},
  {'question': 'What is a deposit and when do I need it?', 'answer': 'A deposit may be required to bid on some auctions. It is held until the auction ends. If you win, it may be applied to the purchase or held until delivery is confirmed. If you don\'t win, it is released back to you.'},
  {'question': 'How do I place a bid?', 'answer': 'Open an active auction, enter your bid amount (it must be at least the minimum increment above the current price), and tap Place Bid. You must have completed KYC and met any deposit requirement.'},
  {'question': 'What happens when I win an auction?', 'answer': 'You will need to confirm the purchase, pay the final price and any buyer commission, and accept the sale agreement. Once the seller ships and you confirm delivery, the transaction is complete.'},
  {'question': 'What fees apply?', 'answer': 'Sellers pay a listing fee when an auction goes live. When an item sells, commission may apply (shown at listing and checkout). All fees are displayed before you commit.'},
  {'question': 'How do I list an item?', 'answer': 'Go to Create Auction, add photos and details, set a start price and duration, and submit for approval. Once approved, pay the listing fee to make the auction live.'},
  {'question': 'Can I cancel a bid?', 'answer': 'Bids are binding. Only place a bid if you intend to buy at that price if you win. Contact support in exceptional circumstances.'},
  {'question': 'How do I get help?', 'answer': 'Use the Contact Us page to email support or submit a message. You can also use Live Chat from the More tab to message the support team.'},
];

/// Help & FAQ: Firestore faq collection with static fallback and search.
class HelpFaqPage extends StatefulWidget {
  const HelpFaqPage({super.key});

  @override
  State<HelpFaqPage> createState() => _HelpFaqPageState();
}

class _HelpFaqPageState extends State<HelpFaqPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> _getItems(QuerySnapshot? snapshot) {
    if (snapshot != null && snapshot.docs.isNotEmpty) {
      final list = snapshot.docs.map((d) {
        final data = d.data() as Map<String, dynamic>;
        return <String, String>{
          'question': data['question'] as String? ?? 'Question',
          'answer': data['answer'] as String? ?? '',
        };
      }).toList();
      list.sort((a, b) => (a['question'] ?? '').compareTo(b['question'] ?? ''));
      return list;
    }
    return _staticFaq;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: const UnifiedAppBar(title: 'Help & FAQ'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search FAQ...',
                prefixIcon: const Icon(Icons.search, size: 22),
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('faq').snapshots(),
              builder: (context, snapshot) {
                final items = snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty
                    ? _staticFaq
                    : _getItems(snapshot.data);
                final query = _searchController.text.trim().toLowerCase();
                final filtered = query.isEmpty
                    ? items
                    : items.where((item) {
                        final q = (item['question'] ?? '').toLowerCase();
                        final a = (item['answer'] ?? '').toLowerCase();
                        return q.contains(query) || a.contains(query);
                      }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No results for "$query"',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _FaqTile(
                      question: item['question'] ?? 'Question',
                      answer: item['answer'] ?? '',
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatefulWidget {
  final String question;
  final String answer;

  const _FaqTile({required this.question, required this.answer});

  @override
  State<_FaqTile> createState() => _FaqTileState();
}

class _FaqTileState extends State<_FaqTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.question,
                        style:
                            Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.textPrimary,
                                ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
                if (_expanded) ...[
                  const SizedBox(height: 12),
                  Text(
                    widget.answer,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
