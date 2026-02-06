import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../widgets/unified_app_bar.dart';

/// Static FAQ entries (used when Firestore is empty or fails).
/// Final version – matches Help & FAQ content.
final List<Map<String, String>> _staticFaq = [
  {
    'question': 'What is M Auction?',
    'answer': 'M Auction is a digital auction platform that connects buyers and sellers of luxury and high-value items such as watches, bags, art, jewellery, and collectibles.\n\n'
        'The platform allows sellers to list items and buyers to place bids. M Auction acts solely as a technology intermediary and does not sell, purchase, inspect, or guarantee any items listed on the platform.',
  },
  {
    'question': 'How does M Auction work?',
    'answer': 'Sellers create auction listings by adding item details, images, and a starting price.\n'
        'Buyers can browse auctions freely and place bids on active listings.\n'
        'When an auction ends, the highest bidder wins and proceeds to complete the transaction directly with the seller according to the agreed terms.\n\n'
        'M Auction facilitates the process by providing the platform, verification steps, and agreement records, but does not take ownership of any item or participate in the physical exchange.',
  },
  {
    'question': 'Do I need to verify my identity?',
    'answer': 'Yes. Identity verification (KYC) is required to place bids or list items.\n'
        'This helps reduce fraud and ensures that users on the platform are real and accountable.',
  },
  {
    'question': 'What is a deposit and when is it required?',
    'answer': 'Some auctions may require a refundable deposit to place bids.\n'
        'Deposits help ensure serious bidding behavior.\n'
        'If you do not win the auction, the deposit is released back to you according to the platform rules.',
  },
  {
    'question': 'How do I place a bid?',
    'answer': 'Open an active auction, select or enter your bid amount (following the minimum increment rules), and tap Place Bid.\n\n'
        'Before bidding, you must:\n'
        '• Be logged in\n'
        '• Complete required verification steps\n'
        '• Accept the Terms & Conditions\n'
        '• Meet any deposit requirements\n\n'
        'All bids are binding commitments.',
  },
  {
    'question': 'What happens when I win an auction?',
    'answer': 'When you win an auction:\n'
        '• You commit to purchasing the item at your winning bid price\n'
        '• You and the seller are responsible for confirming item details, payment, and delivery\n'
        '• Once both parties confirm completion, the transaction is considered final\n\n'
        'M Auction does not guarantee the item condition, authenticity, or delivery and is not a party to the sale contract.',
  },
  {
    'question': 'What fees apply?',
    'answer': 'Sellers may be charged a listing fee to publish an auction.\n'
        'Additional commissions or fees may apply and will always be clearly displayed before you confirm any action.\n'
        'All users are responsible for reviewing and accepting applicable fees before proceeding.',
  },
  {
    'question': 'How do I list an item?',
    'answer': 'To list an item:\n'
        '1. Sign in using your mobile number\n'
        '2. Verify your email and complete required profile details\n'
        '3. Accept the Terms & Conditions\n'
        '4. Create the listing with accurate information and images\n'
        '5. Pay the listing fee (if applicable)\n'
        '6. Complete any required verification steps\n\n'
        'All listings are subject to review and approval before going live.',
  },
  {
    'question': 'Can I cancel a bid?',
    'answer': 'Bids are binding and should only be placed if you fully intend to purchase the item if you win.\n'
        'In exceptional circumstances, you may contact support, but bid cancellation is not guaranteed.',
  },
  {
    'question': 'What happens in case of fraud or disputes?',
    'answer': 'M Auction takes fraud prevention seriously.\n'
        'If suspicious activity, fraud, or misuse is detected:\n'
        '• The platform may suspend the transaction or involved accounts\n'
        '• User access may be restricted or terminated\n'
        '• Relevant user data may be shared with the affected party or official authorities where legally required\n\n'
        'Responsibility for verifying items, agreements, and payments lies fully with the buyer and seller.',
  },
  {
    'question': 'Is M Auction responsible for the transaction?',
    'answer': 'No.\n'
        'M Auction is a technology platform that facilitates communication and bidding between users.\n'
        'The platform does not:\n'
        '• Own listed items\n'
        '• Inspect or authenticate products\n'
        '• Guarantee payments or delivery\n\n'
        'All legal responsibility rests with the buyer and seller.',
  },
  {
    'question': 'How do I get help?',
    'answer': 'If you need assistance:\n'
        '• Use the Contact Us page to send a message or email support\n'
        '• Use Live Chat from the More tab for direct support during available hours',
  },
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
