import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'unified_app_bar.dart';

/// Content padding — matches app theme card horizontal margin (20).
const double kAdminContentPadding = 20;

/// Standard vertical spacing between list items / cards — matches theme card vertical margin (12).
const double kAdminCardSpacing = 12;

/// Standard card margin — matches ThemeData.cardTheme (horizontal: 20, vertical: 12).
const EdgeInsets kAdminCardMargin = EdgeInsets.symmetric(
  horizontal: kAdminContentPadding,
  vertical: kAdminCardSpacing,
);

/// Standard card inner padding — matches app theme (generous, 20).
const EdgeInsets kAdminCardPadding = EdgeInsets.all(20);

/// Section titles for app bar (index 0–6).
const List<String> kAdminSectionTitles = [
  'Auctions',
  'Deposits',
  'KYC',
  'Finance',
  'Ads',
  'Support',
  'Admins',
];

/// Icons for each admin section (0–6).
const List<IconData> kAdminSectionIcons = [
  Icons.gavel_rounded,
  Icons.account_balance_wallet_rounded,
  Icons.verified_user_rounded,
  Icons.attach_money_rounded,
  Icons.campaign_rounded,
  Icons.chat_bubble_outline_rounded,
  Icons.admin_panel_settings_rounded,
];

/// Bottom navigation for admin sections. Uses theme typography (Inter) and design system colors.
class AdminBottomNav extends StatelessWidget {
  const AdminBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.supportUnreadCount = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final int supportUnreadCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final selectedColor = AppTheme.primaryBlue;
    final unselectedColor = AppTheme.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(7, (index) {
              final selected = index == currentIndex;
              final color = selected ? selectedColor : unselectedColor;
              final icon = kAdminSectionIcons[index];
              final label = kAdminSectionTitles[index];
              final isSupport = index == 5;

              return Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onTap(index),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Icon(
                              icon,
                              size: 22,
                              color: color,
                            ),
                            if (isSupport && supportUnreadCount > 0)
                              Positioned(
                                top: -4,
                                right: -6,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: AppTheme.error,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Minimal admin branding footer. Uses app design system: Inter, 13px, w600.
class AdminFooter extends StatelessWidget {
  const AdminFooter({
    super.key,
    this.showBack = false,
    this.onBack,
  });

  final bool showBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.primaryBlue,
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            if (showBack && onBack != null)
              IconButton(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                tooltip: 'Back to Admin',
              ),
            const SizedBox(width: 8),
            Icon(
              Icons.admin_panel_settings_rounded,
              size: 18,
              color: Colors.white.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 8),
            Text(
              'M Auction Admin',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wraps admin screen with optional app bar and persistent footer.
class AdminLayout extends StatelessWidget {
  const AdminLayout({
    super.key,
    required this.child,
    this.title,
    this.showBack = false,
    this.actions,
  });

  final Widget child;
  final String? title;
  final bool showBack;
  final List<Widget>? actions;

  static Widget wrap(Widget page) {
    return Column(
      children: [
        Expanded(child: page),
        const AdminFooter(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: title != null
          ? UnifiedAppBar(
              title: title!,
              automaticallyImplyLeading: !showBack,
              leading: showBack
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null,
              actions: actions,
            )
          : null,
      body: child,
      bottomNavigationBar: AdminFooter(
        showBack: showBack,
        onBack: showBack ? () => Navigator.of(context).maybePop() : null,
      ),
    );
  }
}

/// Shared empty state: icon in circle, title, subtitle. Uses theme typography and 14px radius.
class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconSize = 44,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final double iconSize;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = iconColor ?? AppTheme.textTertiary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kAdminContentPadding * 2),
        child: Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AppTheme.border, width: 1),
          ),
          color: AppTheme.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: iconSize, color: color),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: AppTheme.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
                    textAlign: TextAlign.center,
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

/// Error state for admin sections. Theme typography.
class AdminErrorState extends StatelessWidget {
  const AdminErrorState({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kAdminContentPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline_rounded, size: 48, color: AppTheme.error),
            const SizedBox(height: 14),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 20),
                label: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standard admin list card — matches app theme: radius 14, margin 20/12, padding 20.
class AdminCard extends StatelessWidget {
  const AdminCard({
    super.key,
    required this.child,
    this.margin,
    this.padding,
  });

  final Widget child;
  final EdgeInsets? margin;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardTheme = theme.cardTheme;
    return Card(
      elevation: cardTheme.elevation ?? 0,
      margin: margin ?? kAdminCardMargin,
      shape: cardTheme.shape ?? RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppTheme.border, width: 1),
      ),
      color: cardTheme.color ?? AppTheme.surface,
      child: Padding(
        padding: padding ?? kAdminCardPadding,
        child: child,
      ),
    );
  }
}
