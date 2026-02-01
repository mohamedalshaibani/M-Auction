import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../models/category_model.dart';
import '../theme/app_theme.dart';

class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  final _searchController = TextEditingController();
  final _auctionService = AuctionService();
  final _adminSettings = AdminSettingsService();
  List<CategoryGroup> _categoryGroups = defaultTopLevelCategories;
  String? _selectedCategoryGroupId; // null = All
  String? _selectedSubcategoryId;
  List<Subcategory> _subcategories = [];
  String _selectedFilter = 'Active';

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final list = await _adminSettings.getTopLevelCategories();
      if (mounted) setState(() => _categoryGroups = list);
    } catch (_) {}
  }

  Future<void> _onCategoryGroupTapped(String? groupId) async {
    if (groupId == null) {
      if (mounted) setState(() {
        _selectedCategoryGroupId = null;
        _selectedSubcategoryId = null;
        _subcategories = [];
      });
      return;
    }
    final subs = await _adminSettings.getSubcategories(groupId);
    if (mounted) setState(() {
      _selectedCategoryGroupId = groupId;
      _subcategories = subs;
      _selectedSubcategoryId = null;
    });
  }

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
              width: 90,
              height: 52,
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
            
            // Category grid (6 top-level categories in order)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const crossAxisCount = 2;
                    const spacing = 12.0;
                    const aspectRatio = 1.0;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: aspectRatio,
                      children: [
                        _ExploreCategoryTile(
                          label: 'All',
                          isSelected: _selectedCategoryGroupId == null,
                          onTap: () => _onCategoryGroupTapped(null),
                        ),
                        ..._categoryGroups.map((g) => _ExploreCategoryTile(
                              label: g.nameEn,
                              isSelected: _selectedCategoryGroupId == g.id,
                              onTap: () => _onCategoryGroupTapped(g.id),
                            )),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_selectedCategoryGroupId != null && _subcategories.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('All'),
                          selected: _selectedSubcategoryId == null,
                          onSelected: (_) => setState(() => _selectedSubcategoryId = null),
                          selectedColor: Theme.of(context).colorScheme.primaryContainer,
                          checkmarkColor: AppTheme.primaryBlue,
                          side: BorderSide(
                            color: _selectedSubcategoryId == null ? AppTheme.primaryBlue : AppTheme.border,
                            width: 1,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        const SizedBox(width: 8),
                        ..._subcategories.map((s) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(s.nameEn),
                                selected: _selectedSubcategoryId == s.id,
                                onSelected: (_) => setState(() => _selectedSubcategoryId = s.id),
                                selectedColor: Theme.of(context).colorScheme.primaryContainer,
                                checkmarkColor: AppTheme.primaryBlue,
                                side: BorderSide(
                                  color: _selectedSubcategoryId == s.id ? AppTheme.primaryBlue : AppTheme.border,
                                  width: 1,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            )),
                      ],
                    ),
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
                  debugPrint('ExplorePage: filter=$_selectedFilter, categoryGroup=$_selectedCategoryGroupId');
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
                  
                  // Category filter (categoryGroup + optional subcategory)
                  if (_selectedCategoryGroupId != null) {
                    if (effectiveCategoryGroup(data) != _selectedCategoryGroupId) return false;
                    if (_selectedSubcategoryId != null &&
                        effectiveSubcategory(data) != _selectedSubcategoryId) return false;
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
                        final category = effectiveSubcategory(data);
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

class _ExploreCategoryTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExploreCategoryTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? AppTheme.primaryBlue : AppTheme.border,
              width: isSelected ? 2 : 1,
            ),
            color: isSelected ? AppTheme.primaryBlue.withValues(alpha: 0.08) : AppTheme.surface,
          ),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppTheme.primaryBlue : AppTheme.textPrimary,
                  ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
