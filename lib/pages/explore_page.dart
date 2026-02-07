import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../models/category_model.dart';
import '../models/watch_brand.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/header_logo.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/admin_support_badge.dart';
import '../widgets/watch_brand_picker.dart';

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
  List<WatchBrand> _watchBrands = [];
  String? _selectedWatchBrandId; // null = All (when category is watches)
  // Only active auctions are shown; ended auctions are hidden from Explore

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
        _watchBrands = [];
        _selectedWatchBrandId = null;
      });
      return;
    }
    final subs = await _adminSettings.getSubcategories(groupId);
    final watchBrands = groupId == 'watches' ? await _adminSettings.getWatchBrands() : <WatchBrand>[];
    if (mounted) setState(() {
      _selectedCategoryGroupId = groupId;
      _subcategories = subs;
      _selectedSubcategoryId = null;
      _watchBrands = watchBrands;
      _selectedWatchBrandId = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isEndedState(String state) {
    return state == 'ENDED' || state == 'ENDED_NO_RESPONSE';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UnifiedAppBar(
        titleWidget: HeaderLogo(),
        actions: [AdminSupportBadge()],
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ——— Compact fixed filter section ———
            Container(
              color: AppTheme.backgroundLight,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Search + Active/Ended on one row (compact)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Category chips (horizontal, compact)
                  SizedBox(
                    height: 36,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        _ExploreCategoryChip(
                          label: 'All',
                          isSelected: _selectedCategoryGroupId == null,
                          onTap: () => _onCategoryGroupTapped(null),
                        ),
                        const SizedBox(width: 6),
                        ..._categoryGroups.map((g) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ExploreCategoryChip(
                                label: g.nameEn,
                                isSelected: _selectedCategoryGroupId == g.id,
                                onTap: () => _onCategoryGroupTapped(g.id),
                              ),
                            )),
                      ],
                    ),
                  ),
                  if (_selectedCategoryGroupId != null && _subcategories.length >= 2) ...[
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          _ExploreCategoryChip(
                            label: 'All',
                            isSelected: _selectedSubcategoryId == null,
                            onTap: () => setState(() => _selectedSubcategoryId = null),
                          ),
                          const SizedBox(width: 6),
                          ..._subcategories.map((s) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _ExploreCategoryChip(
                                  label: s.nameEn,
                                  isSelected: _selectedSubcategoryId == s.id,
                                  onTap: () => setState(() => _selectedSubcategoryId = s.id),
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],
                  if (_selectedCategoryGroupId == 'watches' && _watchBrands.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    WatchBrandPicker(
                      brands: _watchBrands,
                      selectedBrandId: _selectedWatchBrandId,
                      onChanged: (value) => setState(() => _selectedWatchBrandId = value),
                      allowAll: true,
                      label: 'Brand',
                    ),
                  ],
                ],
              ),
            ),
            // ——— Auction list (horizontal rows, scrollable) ———
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
              stream: _auctionService.streamActiveAuctionsWithLimit(100),
              builder: (context, snapshot) {
                if (kDebugMode) {
                  debugPrint('ExplorePage: categoryGroup=$_selectedCategoryGroupId');
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 40,
                            color: AppTheme.error,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Error loading auctions',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppTheme.error,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Check your connection. If browsing without signing in, ensure Firestore rules allow public read for auctions.',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              setState(() {});
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    children: List.generate(6, (_) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ExploreRowSkeleton(),
                    )),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 48,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No active auctions yet',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Apply filtering and sorting (stream already returns only ACTIVE)
                final searchQuery = _searchController.text.trim().toLowerCase();
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (!isAuctionOpenForPublicBrowsing(data)) return false;
                  
                  // Category filter (categoryGroup + optional subcategory)
                  if (_selectedCategoryGroupId != null) {
                    if (effectiveCategoryGroupNormalized(data) != _selectedCategoryGroupId!.toLowerCase()) return false;
                    if (_selectedSubcategoryId != null &&
                        effectiveSubcategory(data) != _selectedSubcategoryId) return false;
                  }
                  
                  // Brand filter (when category is watches)
                  if (_selectedCategoryGroupId == 'watches' && _selectedWatchBrandId != null) {
                    final bid = data['brandId'] as String?;
                    final b = data['brand'] as String?;
                    final matchId = bid == _selectedWatchBrandId;
                    String? selectedName;
                    for (final w in _watchBrands) {
                      if (w.id == _selectedWatchBrandId) { selectedName = w.name; break; }
                    }
                    final matchName = selectedName != null && b == selectedName;
                    if (!matchId && !matchName) return false;
                  }
                  
                  // Search filter (title, description, brand)
                  if (searchQuery.isNotEmpty) {
                    final title = (data['title'] as String? ?? '').toLowerCase();
                    final desc = (data['description'] as String? ?? '').toLowerCase();
                    final brand = (effectiveBrandDisplay(data)).toLowerCase();
                    if (!title.contains(searchQuery) &&
                        !desc.contains(searchQuery) &&
                        !brand.contains(searchQuery)) return false;
                  }
                  
                  return true;
                }).toList();

                // Sort: ending soonest first
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
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off,
                            size: 48,
                            color: AppTheme.textTertiary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No auctions match your filters',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  color: AppTheme.textSecondary,
                                ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // Vertical list of wide horizontal cards (easy to scan)
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final auctionId = doc.id;
                    final title = data['title'] as String? ?? 'Untitled';
                    final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
                    final endsAt = data['endsAt'] as Timestamp?;
                    final state = data['state'] as String? ?? '';
                    final isEnded = _isEndedState(state);
                    final images = data['images'] as List<dynamic>?;
                    String? imageUrl;
                    if (images != null && images.isNotEmpty) {
                      for (final e in images) {
                        if (e is Map && (e['isPrimary'] == true)) {
                          imageUrl = e['url'] as String?;
                          break;
                        }
                      }
                      if (imageUrl == null && images.isNotEmpty) {
                        final first = images.first;
                        if (first is Map) imageUrl = first['url'] as String?;
                        else if (first is String) imageUrl = first;
                      }
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ExploreRowCard(
                        auctionId: auctionId,
                        title: title,
                        currentPrice: currentPrice,
                        timeLeft: formatTimeLeftCompact(endsAt),
                        isEnded: isEnded,
                        imageUrl: imageUrl,
                      ),
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

/// Compact chip for category/subcategory filter row.
class _ExploreCategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ExploreCategoryChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? AppTheme.primaryBlue : AppTheme.border,
              width: isSelected ? 1.5 : 1,
            ),
            color: isSelected ? AppTheme.primaryBlue.withValues(alpha: 0.12) : AppTheme.surface,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
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

/// Wide horizontal row card for Explore (vertical list, easy to scan).
class _ExploreRowCard extends StatelessWidget {
  final String auctionId;
  final String title;
  final double currentPrice;
  final String timeLeft;
  final bool isEnded;
  final String? imageUrl;

  const _ExploreRowCard({
    required this.auctionId,
    required this.title,
    required this.currentPrice,
    required this.timeLeft,
    required this.isEnded,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/auctionDetail?auctionId=$auctionId'),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 100,
                  height: 100,
                  child: imageUrl != null && imageUrl!.isNotEmpty
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _ExploreChipPlaceholder(),
                        )
                      : _ExploreChipPlaceholder(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'AED ${formatMoney(currentPrice)}',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppTheme.primaryBlue,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          isEnded ? Icons.check_circle_outline : Icons.access_time,
                          size: 14,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeLeft,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: AppTheme.textSecondary,
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

/// Skeleton for Explore row card (loading state).
class _ExploreRowSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppTheme.backgroundGrey,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 14,
                  width: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundGrey,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 12,
                  width: 60,
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

class _ExploreChipPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundGrey,
      child: Center(child: Icon(Icons.image_outlined, size: 28, color: AppTheme.textTertiary)),
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
                    'AED ${formatMoney(currentPrice)}',
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
