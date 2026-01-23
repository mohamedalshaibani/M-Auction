import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/auction_service.dart';
import '../theme/app_theme.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _searchController = TextEditingController();
  final _auctionService = AuctionService();
  String _selectedCategory = 'All';
  String _selectedFilter = 'Active';
  
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

  bool _isEndedState(String state) {
    return state == 'ENDED' || state == 'ENDED_NO_RESPONSE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SizedBox(
              width: 48,
              height: 28,
              child: Image.asset(
                'assets/branding/logo_light.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 16),
            const Text('Explore'),
          ],
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search field
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
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
                    setState(() {});
                  },
                ),
              ),
            ),
            
            // Active/Ended filter toggle
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _FilterToggle(
                          label: 'Active',
                          isSelected: _selectedFilter == 'Active',
                          onTap: () {
                            setState(() {
                              _selectedFilter = 'Active';
                            });
                          },
                        ),
                      ),
                      Expanded(
                        child: _FilterToggle(
                          label: 'Ended',
                          isSelected: _selectedFilter == 'Ended',
                          onTap: () {
                            setState(() {
                              _selectedFilter = 'Ended';
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 16),
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
            
            // Grid of auction cards
            StreamBuilder<QuerySnapshot>(
              stream: _auctionService.streamAllAuctions(limit: 50),
              builder: (context, snapshot) {
                if (kDebugMode) {
                  debugPrint('ExplorePage: filter=$_selectedFilter, category=$_selectedCategory');
                }

                if (snapshot.hasError) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
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
                              'Error loading auctions',
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
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  // Grid skeleton
                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverGrid(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _SkeletonGridCard(),
                        childCount: 4,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 64,
                              color: AppTheme.textTertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _selectedFilter == 'Active'
                                  ? 'No active auctions yet'
                                  : 'No ended auctions yet',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                // Apply filtering and sorting
                final searchQuery = _searchController.text.trim().toLowerCase();
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final state = data['state'] as String? ?? 'UNKNOWN';
                  
                  // State filter
                  if (_selectedFilter == 'Active') {
                    if (state != 'ACTIVE') return false;
                  } else {
                    if (!_isEndedState(state)) return false;
                  }
                  
                  // Category filter
                  if (_selectedCategory != 'All') {
                    final category = data['category'] as String? ?? '';
                    if (category != _selectedCategory) return false;
                  }
                  
                  // Search filter
                  if (searchQuery.isNotEmpty) {
                    final title = (data['title'] as String? ?? '').toLowerCase();
                    if (!title.contains(searchQuery)) return false;
                  }
                  
                  return true;
                }).toList();

                // Sort
                filteredDocs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aEndsAt = aData['endsAt'] as Timestamp?;
                  final bEndsAt = bData['endsAt'] as Timestamp?;

                  if (aEndsAt == null && bEndsAt == null) return 0;
                  if (aEndsAt == null) return 1;
                  if (bEndsAt == null) return -1;

                  if (_selectedFilter == 'Active') {
                    return aEndsAt.compareTo(bEndsAt);
                  } else {
                    return bEndsAt.compareTo(aEndsAt);
                  }
                });

                if (filteredDocs.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off,
                              size: 64,
                              color: AppTheme.textTertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No auctions match your filters',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: AppTheme.textSecondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 0.75,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final doc = filteredDocs[index];
                        final data = doc.data() as Map<String, dynamic>;
                        final auctionId = doc.id;
                        
                        final title = data['title'] as String? ?? 'Untitled Auction';
                        final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
                        final endsAt = data['endsAt'] as Timestamp?;
                        final state = data['state'] as String? ?? 'UNKNOWN';
                        final category = data['category'] as String? ?? '';
                        // Get primary image URL from images array
                        final images = data['images'] as List<dynamic>?;
                        String? imageUrl;
                        if (images != null && images.isNotEmpty) {
                          // Find primary image, or use first image
                          final primaryImage = images.firstWhere(
                            (img) => img is Map && (img['isPrimary'] == true),
                            orElse: () => images.first,
                          );
                          if (primaryImage is Map) {
                            imageUrl = primaryImage['url'] as String?;
                          } else if (primaryImage is String) {
                            // Legacy format: array of strings
                            imageUrl = primaryImage;
                          }
                        }
                        
                        final isEnded = _isEndedState(state);
                        final timeLeft = isEnded ? 'Ended' : _formatTimeLeft(endsAt);
                        
                        return _ExploreGridCard(
                          auctionId: auctionId,
                          title: title,
                          currentPrice: currentPrice,
                          timeLeft: timeLeft,
                          category: category,
                          imageUrl: imageUrl,
                          isEnded: isEnded,
                        );
                      },
                      childCount: filteredDocs.length,
                    ),
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

class _FilterToggle extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterToggle({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonGridCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.backgroundGrey,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreGridCard extends StatelessWidget {
  final String auctionId;
  final String title;
  final double currentPrice;
  final String timeLeft;
  final String category;
  final String? imageUrl;
  final bool isEnded;

  const _ExploreGridCard({
    required this.auctionId,
    required this.title,
    required this.currentPrice,
    required this.timeLeft,
    required this.category,
    this.imageUrl,
    required this.isEnded,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            '/auctionDetail?auctionId=$auctionId',
          );
        },
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              child: Container(
                width: double.infinity,
                height: 120,
                color: AppTheme.backgroundGrey,
                child: imageUrl != null && imageUrl!.isNotEmpty
                    ? Image.network(
                        imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _ImagePlaceholder();
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
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryBlue),
                            ),
                          );
                        },
                      )
                    : _ImagePlaceholder(),
              ),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  // Price
                  Text(
                    'AED ${currentPrice.toStringAsFixed(0)}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  // Time/Status row
                  Row(
                    children: [
                      if (!isEnded) ...[
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          timeLeft,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.textSecondary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (category.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: AppTheme.primaryBlue,
                              fontSize: 10,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundGrey,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }
}
