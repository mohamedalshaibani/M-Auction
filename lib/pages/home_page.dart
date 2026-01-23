import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/auction_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _auctionService = AuctionService();
  String _selectedCategory = 'All';
  
  // Available categories (can be extracted from Firestore if needed)
  final List<String> _categories = ['All', 'Bags', 'Watches', 'Jewelry', 'Art'];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatTimeLeft(Timestamp? endsAt) {
    if (endsAt == null) return 'No end date';
    
    final now = DateTime.now();
    final endDate = endsAt.toDate();
    final difference = endDate.difference(now);

    if (difference.isNegative) {
      return 'Ended';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ${difference.inHours % 24}h';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ${difference.inMinutes % 60}m';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'Ending soon';
    }
  }

  String _getStatusBadge(String state, Timestamp? endsAt) {
    if (state != 'ACTIVE') return state.toLowerCase();
    
    if (endsAt == null) return 'active';
    
    final now = DateTime.now();
    final endDate = endsAt.toDate();
    final difference = endDate.difference(now);
    
    if (difference.isNegative) {
      return 'ended';
    } else if (difference.inHours < 24) {
      return 'ending_soon';
    } else {
      return 'active';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'active':
        return AppTheme.success;
      case 'ending_soon':
        return AppTheme.warning;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top bar with logo and title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Image.asset(
                      'assets/branding/logo_light.png',
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'M Auction',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Search field
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search auctions...',
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (_) {
                    setState(() {}); // Trigger rebuild for search filtering
                  },
                ),
              ),
            ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
            
            // Category chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: _categories.map((category) {
                    final isSelected = category == _selectedCategory;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(category),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _selectedCategory = category;
                          });
                        },
                        selectedColor: Theme.of(context).colorScheme.primaryContainer,
                        checkmarkColor: AppTheme.primaryBlue,
                        labelStyle: TextStyle(
                          color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryBlue : AppTheme.border,
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
            
            // Auction cards list from Firestore
            StreamBuilder<QuerySnapshot>(
              stream: _auctionService.streamActiveAuctionsFiltered(
                category: _selectedCategory == 'All' ? null : _selectedCategory,
                limit: 50,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Center(
                        child: Text(
                          'Error loading auctions: ${snapshot.error}',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: AppTheme.error,
                              ),
                        ),
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'No active auctions available',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                    ),
                  );
                }

                // Apply search filter and sorting locally
                final searchQuery = _searchController.text.trim().toLowerCase();
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  if (searchQuery.isEmpty) return true;
                  
                  final data = doc.data() as Map<String, dynamic>;
                  final title = (data['title'] as String? ?? '').toLowerCase();
                  return title.contains(searchQuery);
                }).toList();

                // Sort by endsAt if category filter is applied (since Firestore query doesn't include orderBy)
                // This avoids the composite index requirement
                if (_selectedCategory != 'All') {
                  filteredDocs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aEndsAt = aData['endsAt'] as Timestamp?;
                    final bEndsAt = bData['endsAt'] as Timestamp?;

                    if (aEndsAt == null && bEndsAt == null) return 0;
                    if (aEndsAt == null) return 1;
                    if (bEndsAt == null) return -1;

                    return aEndsAt.compareTo(bEndsAt); // Ascending (ending soonest first)
                  });
                }

                if (filteredDocs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Text(
                          'No auctions match your search',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                        ),
                      ),
                    ),
                  );
                }

                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final auctionId = doc.id;
                      
                      // Extract fields with null-safety
                      final title = data['title'] as String? ?? 'Untitled Auction';
                      final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
                      final endsAt = data['endsAt'] as Timestamp?;
                      final state = data['state'] as String? ?? 'UNKNOWN';
                      final images = data['images'] as List<dynamic>?;
                      final imageUrl = images != null && images.isNotEmpty
                          ? images[0] as String?
                          : null;
                      
                      final timeLeft = _formatTimeLeft(endsAt);
                      final status = _getStatusBadge(state, endsAt);
                      
                      return _AuctionCard(
                        auctionId: auctionId,
                        title: title,
                        currentPrice: currentPrice,
                        timeLeft: timeLeft,
                        status: status,
                        imageUrl: imageUrl,
                        statusColor: _getStatusColor(status),
                      );
                    },
                    childCount: filteredDocs.length,
                  ),
                );
              },
            ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuctionCard extends StatelessWidget {
  final String auctionId;
  final String title;
  final double currentPrice;
  final String timeLeft;
  final String status;
  final String? imageUrl;
  final Color statusColor;

  const _AuctionCard({
    required this.auctionId,
    required this.title,
    required this.currentPrice,
    required this.timeLeft,
    required this.status,
    this.imageUrl,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/auctionDetail?auctionId=$auctionId',
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image or placeholder
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundGrey,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.image_outlined,
                              color: AppTheme.textTertiary,
                              size: 40,
                            );
                          },
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                strokeWidth: 2,
                              ),
                            );
                          },
                        ),
                      )
                    : Icon(
                        Icons.image_outlined,
                        color: AppTheme.textTertiary,
                        size: 40,
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
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'AED ${currentPrice.toStringAsFixed(0)}',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
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
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
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
  }
}
