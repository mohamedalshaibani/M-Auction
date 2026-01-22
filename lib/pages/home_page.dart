import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

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
                  readOnly: true,
                  onTap: () {
                    // Placeholder - search functionality to be implemented
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
                  children: [
                    _CategoryChip(label: 'All', isSelected: true),
                    const SizedBox(width: 8),
                    _CategoryChip(label: 'Bags'),
                    const SizedBox(width: 8),
                    _CategoryChip(label: 'Watches'),
                    const SizedBox(width: 8),
                    _CategoryChip(label: 'Jewelry'),
                    const SizedBox(width: 8),
                    _CategoryChip(label: 'Art'),
                  ],
                ),
              ),
            ),
            
            const SliverToBoxAdapter(
              child: SizedBox(height: 20),
            ),
            
            // Auction cards list
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return _AuctionCard(
                    auctionId: 'mock_$index',
                    title: _mockAuctions[index % _mockAuctions.length]['title']!,
                    currentPrice: _mockAuctions[index % _mockAuctions.length]['currentPrice']!,
                    timeLeft: _mockAuctions[index % _mockAuctions.length]['timeLeft']!,
                    status: _mockAuctions[index % _mockAuctions.length]['status']!,
                  );
                },
                childCount: 10, // Show 10 mock auctions
              ),
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

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool isSelected;

  const _CategoryChip({
    required this.label,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        // Placeholder - category filtering to be implemented
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
    );
  }
}

class _AuctionCard extends StatelessWidget {
  final String auctionId;
  final String title;
  final double currentPrice;
  final String timeLeft;
  final String status;

  const _AuctionCard({
    required this.auctionId,
    required this.title,
    required this.currentPrice,
    required this.timeLeft,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    switch (status) {
      case 'active':
        statusColor = AppTheme.success;
        break;
      case 'ending_soon':
        statusColor = AppTheme.warning;
        break;
      default:
        statusColor = AppTheme.textSecondary;
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: InkWell(
        onTap: () {
          // Navigate to auction detail (will use real auctionId when available)
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
              // Image placeholder
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundGrey,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
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

// Mock data
final List<Map<String, dynamic>> _mockAuctions = [
  {
    'title': 'Vintage Hermès Birkin Bag',
    'currentPrice': 45000.0,
    'timeLeft': '2d 5h',
    'status': 'active',
  },
  {
    'title': 'Rolex Submariner Date',
    'currentPrice': 28000.0,
    'timeLeft': '1d 12h',
    'status': 'ending_soon',
  },
  {
    'title': 'Cartier Love Bracelet',
    'currentPrice': 12000.0,
    'timeLeft': '5d 3h',
    'status': 'active',
  },
  {
    'title': 'Chanel Classic Flap Bag',
    'currentPrice': 8500.0,
    'timeLeft': '3d 8h',
    'status': 'active',
  },
];
