import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Unified header style across all pages: white background, dark text/icons, no elevation.
/// Use [title] for a text title, or [titleWidget] for custom content (e.g. HeaderLogo).
class UnifiedAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;

  const UnifiedAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions,
    this.bottom,
    this.automaticallyImplyLeading = true,
  }) : assert(title != null || titleWidget != null, 'Provide title or titleWidget');

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appBarTheme = theme.appBarTheme;
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: AppTheme.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: leading != null ? false : automaticallyImplyLeading,
      leading: leading,
      title: titleWidget ?? (title != null
          ? Text(
              title!,
              style: (appBarTheme.titleTextStyle ?? theme.textTheme.titleLarge)?.copyWith(
                    color: appBarTheme.foregroundColor ?? AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
            )
          : null),
      actions: actions,
      bottom: bottom,
    );
  }
}
