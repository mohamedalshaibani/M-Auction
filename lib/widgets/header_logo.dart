import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Header logo for white AppBar. Uses full-color logo (no background box).
class HeaderLogo extends StatelessWidget {
  const HeaderLogo({super.key});

  static const double _logoWidth = 112;
  static const double _logoHeight = 60;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _logoWidth,
      height: _logoHeight,
      child: Image.asset(
        AppTheme.logoAssetSource,
        fit: BoxFit.contain,
      ),
    );
  }
}
