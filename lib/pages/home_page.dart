import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/header_logo.dart';
import '../widgets/unified_app_bar.dart';
import '../widgets/watch_brand_picker.dart';
import '../services/auction_service.dart';
import '../services/admin_settings_service.dart';
import '../services/ads_service.dart';
import '../models/category_model.dart';
import '../models/watch_brand.dart';
import 'listing_flow_gate_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _auctionService = AuctionService();
  final _adminSettings = AdminSettingsService();
  List<CategoryGroup> _categoryGroups = defaultTopLevelCategories;
  bool _searchExpanded = false;
  Map<String, int> _categoryCounts = {};
  StreamSubscription<QuerySnapshot>? _countsSubscription;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _subscribeCategoryCounts();
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus && mounted) {
        setState(() => _searchExpanded = false);
      }
    });
  }

  Future<void> _loadCategories() async {
    try {
      final list = await _adminSettings.getTopLevelCategories();
      if (mounted) setState(() => _categoryGroups = list);
    } catch (_) {}
  }

  void _subscribeCategoryCounts() {
    _countsSubscription?.cancel();
    _countsSubscription = _auctionService.streamActiveAuctionsWithLimit(500).listen((snapshot) {
      if (!mounted) return;
      final counts = <String, int>{};
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        if (!isAuctionOpenForPublicBrowsing(data)) continue;
        final group = effectiveCategoryGroupNormalized(data);
        counts[group] = (counts[group] ?? 0) + 1;
      }
      setState(() => _categoryCounts = counts);
    });
  }

  @override
  void dispose() {
    _countsSubscription?.cancel();
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const UnifiedAppBar(titleWidget: HeaderLogo()),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search at top
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: () {
                      setState(() => _searchExpanded = true);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _searchFocusNode.requestFocus();
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        children: [
                          Icon(Icons.search, size: 20, color: Colors.grey.shade600),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Search auctions...',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey.shade600,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_searchExpanded)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    decoration: InputDecoration(
                      hintText: 'Search auctions...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
            // Browse options (categories grid)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const crossAxisCount = 3;
                    const spacing = 10.0;
                    const aspectRatio = 0.82;
                    return GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: crossAxisCount,
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: aspectRatio,
                      children: _categoryGroups.map((group) {
                        final count = _categoryCounts[group.id] ?? 0;
                        return _CategoryTile(
                          categoryGroup: group,
                          activeCount: count,
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
            // Create Auction button
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ListingFlowGatePage(),
                      ),
                    ),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Create Auction'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            // Horizontal carousel: Browse auctions
            SliverToBoxAdapter(
              child: StreamBuilder<QuerySnapshot>(
                stream: _auctionService.streamActiveAuctionsWithLimit(30),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      child: Text(
                        'Unable to load auctions. Check your connection.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                      ),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  var docs = snapshot.data!.docs
                      .where((d) => isAuctionOpenForPublicBrowsing(d.data() as Map<String, dynamic>))
                      .toList();
                  if (docs.isEmpty) return const SizedBox.shrink();
                  docs = List.from(docs)..shuffle();
                  final take = docs.take(12).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          'Browse auctions',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: _kHomeCarouselTotalHeight,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: take.length,
                          itemBuilder: (context, index) {
                            final doc = take[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final auctionId = doc.id;
                            final title = data['title'] as String? ?? 'Untitled';
                            final price = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
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
                                if (first is Map) {
                                  imageUrl = first['url'] as String?;
                                } else if (first is String) {
                                  imageUrl = first;
                                }
                              }
                            }
                            return Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: _HomeAuctionChip(
                                auctionId: auctionId,
                                title: title,
                                price: price,
                                imageUrl: imageUrl,
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            // Ads section: one banner per partner from Firestore
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'Partners',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  StreamBuilder<List<PartnerAd>>(
                    stream: streamPartnerAdsOnePerPartner(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Text(
                            'No ads available',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Text(
                            'No ads available',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final ads = snapshot.data!;
                      return Column(
                        children: [
                          ...ads.map((ad) => _PartnerBanner(ad: ad)),
                          const SizedBox(height: 24),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Premium category tile for the home grid (tappable, shows active count).
class _CategoryTile extends StatelessWidget {
  final CategoryGroup categoryGroup;
  final int activeCount;
  final VoidCallback onTap;

  const _CategoryTile({
    required this.categoryGroup,
    this.activeCount = 0,
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
                  size: 28,
                  color: AppTheme.primaryBlue,
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    categoryGroup.nameEn,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0.2,
                        ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$activeCount active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
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

/// Full-width partner banner (one per partner). Tappable if linkUrl set.
class _PartnerBanner extends StatelessWidget {
  static const double _bannerHeight = 72;
  final PartnerAd ad;

  const _PartnerBanner({required this.ad});

  @override
  Widget build(BuildContext context) {
    final useImage = ad.imageUrl.isNotEmpty;
    Widget child = Container(
      width: double.infinity,
      height: _bannerHeight,
      decoration: BoxDecoration(
        color: AppTheme.backgroundGrey,
        border: Border(
          top: BorderSide(color: AppTheme.border),
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: useImage
          ? Image.network(
              ad.imageUrl,
              fit: BoxFit.cover,
              width: double.infinity,
              height: _bannerHeight,
              errorBuilder: (_, __, ___) => Center(
                child: Icon(Icons.campaign_outlined, size: 28, color: AppTheme.textTertiary),
              ),
            )
          : Center(
              child: Icon(Icons.campaign_outlined, size: 28, color: AppTheme.textTertiary),
            ),
    );
    final linkUrl = ad.linkUrl;
    if (linkUrl != null && linkUrl.isNotEmpty) {
      child = InkWell(
        onTap: () async {
          final uri = Uri.tryParse(linkUrl);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: child,
      );
    }
    return child;
  }
}

// Fixed dimensions for Browse auctions carousel cards (uniform height + center-crop)
const double _kHomeCarouselCardWidth = 140;
const double _kHomeCarouselImageHeight = 96; // Reduced to account for 2px border (1px top + 1px bottom)
const double _kHomeCarouselTextHeight = 82; // total for title + price block  
const double _kHomeCarouselTotalHeight = 180;

/// Compact auction chip for home horizontal carousel. All sizes fixed to prevent overflow.
class _HomeAuctionChip extends StatelessWidget {
  final String auctionId;
  final String title;
  final double price;
  final String? imageUrl;

  const _HomeAuctionChip({
    required this.auctionId,
    required this.title,
    required this.price,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/auctionDetail?auctionId=$auctionId'),
        child: Container(
          width: _kHomeCarouselCardWidth,
          height: _kHomeCarouselTotalHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image: fixed height, center-crop
              SizedBox(
                height: _kHomeCarouselImageHeight,
                width: _kHomeCarouselCardWidth,
                child: ClipRect(
                  child: imageUrl != null && imageUrl!.isNotEmpty
                      ? Image.network(
                          imageUrl!,
                          fit: BoxFit.cover,
                          alignment: Alignment.center,
                          width: _kHomeCarouselCardWidth,
                          height: _kHomeCarouselImageHeight,
                          errorBuilder: (_, __, ___) => _ChipImagePlaceholder(height: _kHomeCarouselImageHeight),
                        )
                      : _ChipImagePlaceholder(height: _kHomeCarouselImageHeight),
                ),
              ),
              // Text block: fixed height; clip so line-height/rounding never causes overflow
              SizedBox(
                height: _kHomeCarouselTextHeight,
                child: ClipRect(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title: max 2 lines (allow ~38px for line height)
                        SizedBox(
                          height: 38,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Price: single line
                        SizedBox(
                          height: 20,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'AED ${formatMoney(price)}',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppTheme.primaryBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipImagePlaceholder extends StatelessWidget {
  const _ChipImagePlaceholder({this.height});

  final double? height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: height != null ? _kHomeCarouselCardWidth : null,
      child: Container(
        color: AppTheme.backgroundGrey,
        child: Center(child: Icon(Icons.image_outlined, size: 32, color: AppTheme.textTertiary)),
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
                  Text(
                    'AED ${formatMoney(currentPrice)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.primaryBlue,
                          fontWeight: FontWeight.bold,
                        ),
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
  List<WatchBrand> _watchBrands = [];
  String? _selectedWatchBrandId; // null = All (when category is watches)

  @override
  void initState() {
    super.initState();
    _loadSubcategories();
  }

  Future<void> _loadSubcategories() async {
    try {
      final list = await _adminSettings.getSubcategories(widget.categoryGroupId);
      final watchBrands = widget.categoryGroupId == 'watches'
          ? await _adminSettings.getWatchBrands()
          : <WatchBrand>[];
      if (mounted) setState(() {
        _subcategories = list;
        _watchBrands = watchBrands;
      });
    } catch (_) {}
  }

  bool _isEndedState(String state) =>
      state == 'ENDED' || state == 'ENDED_NO_RESPONSE';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: UnifiedAppBar(
        title: '${widget.categoryGroupName} Auctions',
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: AppTheme.backgroundLight,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_subcategories.length >= 2) ...[
                    SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
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
                    if (widget.categoryGroupId == 'watches' && _watchBrands.isNotEmpty)
                      const SizedBox(height: 10),
                  ],
                  if (widget.categoryGroupId == 'watches' && _watchBrands.isNotEmpty)
                    WatchBrandPicker(
                      brands: _watchBrands,
                      selectedBrandId: _selectedWatchBrandId,
                      onChanged: (value) => setState(() => _selectedWatchBrandId = value),
                      allowAll: true,
                      label: 'Brand',
                    ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: widget.auctionService.streamActiveAuctionsWithLimit(100),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline, size: 44, color: AppTheme.error),
                            const SizedBox(height: 12),
                            Text(
                              'Error loading auctions',
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: AppTheme.error,
                                  ),
                              textAlign: TextAlign.center,
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
                              onPressed: () => setState(() {}),
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
                      children: List.generate(5, (_) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CategoryRowSkeleton(),
                      )),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _CategoryEmptyState(categoryName: widget.categoryGroupName);
                  }
                  final groupId = widget.categoryGroupId;
                  final groupIdNorm = groupId.toLowerCase();
                  final subId = _selectedSubcategoryId;
                  final brandId = _selectedWatchBrandId;
                  final filteredDocs = snapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (!isAuctionOpenForPublicBrowsing(data)) return false;
                    if (effectiveCategoryGroupNormalized(data) != groupIdNorm) return false;
                    if (subId != null && effectiveSubcategory(data) != subId) return false;
                    if (groupId == 'watches' && brandId != null) {
                      final bid = data['brandId'] as String?;
                      final b = data['brand'] as String?;
                      final matchId = bid == brandId;
                      String? selectedName;
                      for (final w in _watchBrands) {
                        if (w.id == brandId) { selectedName = w.name; break; }
                      }
                      final matchName = selectedName != null && b == selectedName;
                      if (!matchId && !matchName) return false;
                    }
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
                    return _CategoryEmptyState(categoryName: widget.categoryGroupName);
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final auctionId = doc.id;
                      final title = data['title'] as String? ?? 'Untitled Auction';
                      final currentPrice = (data['currentPrice'] as num?)?.toDouble() ?? 0.0;
                      final endsAt = data['endsAt'] as Timestamp?;
                      final state = data['state'] as String? ?? 'UNKNOWN';
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
                      final timeLeft = isEnded ? 'Ended' : formatTimeLeftCompact(endsAt);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _CategoryListingRowCard(
                          auctionId: auctionId,
                          title: title,
                          currentPrice: currentPrice,
                          timeLeft: timeLeft,
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
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
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

/// Wide horizontal row card for category listing (matches Explore premium style).
class _CategoryListingRowCard extends StatelessWidget {
  final String auctionId;
  final String title;
  final double currentPrice;
  final String timeLeft;
  final bool isEnded;
  final String? imageUrl;

  const _CategoryListingRowCard({
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
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
                          errorBuilder: (_, __, ___) => _CategoryRowImagePlaceholder(),
                        )
                      : _CategoryRowImagePlaceholder(),
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

class _CategoryRowImagePlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.backgroundGrey,
      child: Center(
        child: Icon(Icons.image_outlined, size: 28, color: AppTheme.textTertiary),
      ),
    );
  }
}

/// Skeleton for category listing row (loading state).
class _CategoryRowSkeleton extends StatelessWidget {
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

/// Empty state for category listing (premium style).
class _CategoryEmptyState extends StatelessWidget {
  final String categoryName;

  const _CategoryEmptyState({required this.categoryName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 48, color: AppTheme.textTertiary),
              const SizedBox(height: 16),
              Text(
                'No active auctions in $categoryName',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Check back later or browse other categories',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textTertiary,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
