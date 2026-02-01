import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../theme/app_theme.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../models/category_model.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _auctionService = AuctionService();
  final _adminSettings = AdminSettingsService();
  List<CategoryGroup> _categoryGroups = defaultTopLevelCategories;

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
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Top bar with logo and title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 52,
                      child: Image.asset(
                        'assets/branding/logo_light.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(width: 16),
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
            
            // Category grid (square/rectangular tiles)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const crossAxisCount = 2;
                    const spacing = 12.0;
                    final width = (constraints.maxWidth - spacing) / crossAxisCount;
                    const aspectRatio = 1.0; // square tiles
                    final tileHeight = width / aspectRatio;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: aspectRatio,
                      children: _categoryGroups.map((group) {
                        return _CategoryTile(
                          categoryGroup: group,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (context) => _CategoryListingPage(
                                  categoryGroupId: group.id,
                                  categoryGroupName: group.nameEn,
                                  auctionService: _auctionService,
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
            
            // Auction cards list from Firestore (all active, no category filter)
            StreamBuilder<QuerySnapshot>(
              stream: _auctionService.streamAllAuctions(limit: 50),
              builder: (context, snapshot) {
                if (kDebugMode) {
                  debugPrint('HomePage: loading auctions');
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
                                setState(() {}); // Retry by rebuilding
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
                  // Skeleton loading cards
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _SkeletonCard(),
                      childCount: 3,
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
                              'No active auctions yet',
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

                // Apply filtering: active only, optional search
                final searchQuery = _searchController.text.trim().toLowerCase();
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final state = data['state'] as String? ?? 'UNKNOWN';
                  if (state != 'ACTIVE') return false;
                  if (searchQuery.isNotEmpty) {
                    final title = (data['title'] as String? ?? '').toLowerCase();
                    if (!title.contains(searchQuery)) return false;
                  }
                  return true;
                }).toList();

                // Sort by endsAt ascending (ending soonest first)
                filteredDocs.sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aEndsAt = aData['endsAt'] as Timestamp?;
                  final bEndsAt = bData['endsAt'] as Timestamp?;
                  if (aEndsAt == null && bEndsAt == null) return 0;
                  if (aEndsAt == null) return 1;
                  if (bEndsAt == null) return -1;
                  return aEndsAt.compareTo(bEndsAt);
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
                      
                      return _AuctionCard(
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

/// Premium category tile for the home grid (square/rectangular, tappable).
class _CategoryTile extends StatelessWidget {
  final CategoryGroup categoryGroup;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.categoryGroup,
    required this.onTap,
  });

  IconData get _iconForCategory {
    switch (categoryGroup.id) {
      case 'bags':
        return Icons.shopping_bag_outlined;
      case 'watches':
        return Icons.watch_outlined;
      case 'fashion':
        return Icons.checkroom_outlined;
      case 'jewelry':
        return Icons.diamond_outlined;
      case 'accessories':
        return Icons.style_outlined;
      case 'collectibles':
        return Icons.collections_outlined;
      default:
        return Icons.category_outlined;
    }
  }

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
            border: Border.all(color: AppTheme.border, width: 1),
            color: AppTheme.surface,
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _iconForCategory,
                  size: 36,
                  color: AppTheme.primaryBlue,
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    categoryGroup.nameEn,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0.25,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          Container(
            width: double.infinity,
            height: 200,
            decoration: BoxDecoration(
              color: AppTheme.backgroundGrey,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
          ),
          // Content skeleton
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 120,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 100,
                  height: 16,
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

class _AuctionCard extends StatelessWidget {
  final String auctionId;
  final String title;
  final double currentPrice;
  final String timeLeft;
  final String category;
  final String? imageUrl;
  final bool isEnded;

  const _AuctionCard({
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
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
            // Full-width image
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
              child: Container(
                width: double.infinity,
                height: 200,
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  // Price row
                  Row(
                    children: [
                      Text(
                        'AED ',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                      Text(
                        currentPrice.toStringAsFixed(0),
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Time/status row
                  Row(
                    children: [
                      if (!isEnded) ...[
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        timeLeft,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textSecondary,
                            ),
                      ),
                      const Spacer(),
                      // Category badge
                      if (category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.primaryBlue.withValues(alpha: 0.2),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            category,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppTheme.primaryBlue,
                                  fontWeight: FontWeight.w500,
                                ),
                          ),
                        ),
                      if (isEnded) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.textSecondary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'ENDED',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
          size: 48,
          color: AppTheme.textTertiary,
        ),
      ),
    );
  }
}

/// Full-screen listing for a category group with optional subcategory filter.
class _CategoryListingPage extends StatefulWidget {
  final String categoryGroupId;
  final String categoryGroupName;
  final AuctionService auctionService;

  const _CategoryListingPage({
    required this.categoryGroupId,
    required this.categoryGroupName,
    required this.auctionService,
  });

  @override
  State<_CategoryListingPage> createState() => _CategoryListingPageState();
}

class _CategoryListingPageState extends State<_CategoryListingPage> {
  final _adminSettings = AdminSettingsService();
  List<Subcategory> _subcategories = [];
  String? _selectedSubcategoryId; // null = All

  @override
  void initState() {
    super.initState();
    _loadSubcategories();
  }

  Future<void> _loadSubcategories() async {
    try {
      final list = await _adminSettings.getSubcategories(widget.categoryGroupId);
      if (mounted) setState(() => _subcategories = list);
    } catch (_) {}
  }

  String _formatTimeLeft(Timestamp? endsAt) {
    if (endsAt == null) return 'No end date';
    final now = DateTime.now();
    final endDate = endsAt.toDate();
    final difference = endDate.difference(now);
    if (difference.isNegative) return 'Ended';
    if (difference.inDays > 0) return '${difference.inDays}d ${difference.inHours % 24}h';
    if (difference.inHours > 0) return '${difference.inHours}h ${difference.inMinutes % 60}m';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m';
    return 'Ending soon';
  }

  bool _isEndedState(String state) =>
      state == 'ENDED' || state == 'ENDED_NO_RESPONSE';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.categoryGroupName} Auctions'),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_subcategories.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SubcategoryChip(
                        label: 'All',
                        isSelected: _selectedSubcategoryId == null,
                        onTap: () => setState(() => _selectedSubcategoryId = null),
                      ),
                      const SizedBox(width: 8),
                      ..._subcategories.map((s) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _SubcategoryChip(
                              label: s.nameEn,
                              isSelected: _selectedSubcategoryId == s.id,
                              onTap: () => setState(() => _selectedSubcategoryId = s.id),
                            ),
                          )),
                    ],
                  ),
                ),
              ),
            ],
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: widget.auctionService.streamAllAuctions(limit: 50),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                          const SizedBox(height: 16),
                          Text(
                            'Error loading auctions',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.error,
                                ),
                          ),
                        ],
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return ListView.builder(
                      itemCount: 3,
                      itemBuilder: (_, __) => _SkeletonCard(),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textTertiary),
                          const SizedBox(height: 16),
                          Text(
                            'No active auctions in ${widget.categoryGroupName}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  final groupId = widget.categoryGroupId;
                  final subId = _selectedSubcategoryId;
                  final filteredDocs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final state = data['state'] as String? ?? 'UNKNOWN';
                    if (state != 'ACTIVE') return false;
                    if (effectiveCategoryGroup(data) != groupId) return false;
                    if (subId != null && effectiveSubcategory(data) != subId) return false;
                    return true;
                  }).toList();
                  filteredDocs.sort((a, b) {
                    final aData = a.data() as Map<String, dynamic>;
                    final bData = b.data() as Map<String, dynamic>;
                    final aEndsAt = aData['endsAt'] as Timestamp?;
                    final bEndsAt = bData['endsAt'] as Timestamp?;
                    if (aEndsAt == null && bEndsAt == null) return 0;
                    if (aEndsAt == null) return 1;
                    if (bEndsAt == null) return -1;
                    return aEndsAt.compareTo(bEndsAt);
                  });
                  if (filteredDocs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: AppTheme.textTertiary),
                          const SizedBox(height: 16),
                          Text(
                            'No active auctions in ${widget.categoryGroupName}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final auctionId = doc.id;
                      final title = data['title'] as String? ?? 'Untitled Auction';
                      final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
                      final endsAt = data['endsAt'] as Timestamp?;
                      final state = data['state'] as String? ?? 'UNKNOWN';
                      final displayCategory = effectiveSubcategory(data);
                      final images = data['images'] as List<dynamic>?;
                      String? imageUrl;
                      if (images != null && images.isNotEmpty) {
                        final primaryImage = images.firstWhere(
                          (img) => img is Map && (img['isPrimary'] == true),
                          orElse: () => images.first,
                        );
                        if (primaryImage is Map) {
                          imageUrl = primaryImage['url'] as String?;
                        } else if (primaryImage is String) {
                          imageUrl = primaryImage;
                        }
                      }
                      final isEnded = _isEndedState(state);
                      final timeLeft = isEnded ? 'Ended' : _formatTimeLeft(endsAt);
                      return _AuctionCard(
                        auctionId: auctionId,
                        title: title,
                        currentPrice: currentPrice,
                        timeLeft: timeLeft,
                        category: displayCategory,
                        imageUrl: imageUrl,
                        isEnded: isEnded,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubcategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SubcategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }
}
