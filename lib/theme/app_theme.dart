import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M Auction Design System
/// Luxury tech aesthetic - Professional, trustworthy, modern (2025/2026 style)
/// Based on the brand logo with sophisticated blue palette
class AppTheme {
  // Luxury Color Palette - Based on logo blue gradient
  // Primary: Premium deep blue from logo (single source for all AppBars/headers)
  static const Color primaryBlue = Color(0xFF0B5ED7); // Premium deep blue
  static const Color primaryBlueDark = Color(0xFF0948A8); // Deeper variant
  static const Color primaryBlueLight = Color(0xFF3B82F6); // Lighter blue accent

  // Header logo - consistent size across all pages for clear visibility
  static const double headerLogoWidth = 96;
  static const double headerLogoHeight = 52;
  static const String logoAssetLight = 'assets/branding/logo_light.png';
  
  // Secondary: Elegant blue-grey accent
  static const Color secondaryBlue = Color(0xFF546E7A); // Sophisticated blue-grey
  static const Color secondaryBlueDark = Color(0xFF37474F);
  static const Color secondaryBlueLight = Color(0xFF78909C);
  
  // Soft Background colors (luxury - premium palette)
  static const Color backgroundLight = Color(0xFFF7F8FA); // Soft background
  static const Color backgroundGrey = Color(0xFFF5F5F5); // Very light grey
  static const Color surface = Color(0xFFFFFFFF); // Pure white for cards/surfaces
  static const Color surfaceElevated = Color(0xFFFFFFFF); // Elevated surfaces
  
  // Text colors
  static const Color textPrimary = Color(0xFF1A1A1A); // Deep charcoal (softer than pure black)
  static const Color textSecondary = Color(0xFF616161); // Medium grey
  static const Color textTertiary = Color(0xFF9E9E9E); // Light grey
  static const Color textDisabled = Color(0xFFBDBDBD);
  
  // Semantic colors (refined for luxury feel)
  static const Color success = Color(0xFF2E7D32); // Deeper, more professional green
  static const Color error = Color(0xFFC62828); // Refined red
  static const Color warning = Color(0xFFF57C00); // Warm orange
  static const Color info = Color(0xFF1565C0); // Matches primary
  
  // Border and divider (softer, more subtle)
  static const Color border = Color(0xFFE8E8E8); // Softer border
  static const Color divider = Color(0xFFE0E0E0); // Subtle divider

  /// Get the app theme
  static ThemeData get lightTheme {
    // Inter font family for modern, clean typography
    final textTheme = GoogleFonts.interTextTheme();
    
    return ThemeData(
      useMaterial3: true,
      
      // Color Scheme
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        onPrimary: Colors.white,
        primaryContainer: const Color(0xFFD6E4FF), // Light blue container
        onPrimaryContainer: primaryBlueDark,
        secondary: secondaryBlue,
        onSecondary: Colors.white,
        secondaryContainer: secondaryBlueLight.withValues(alpha: 0.1),
        onSecondaryContainer: secondaryBlueDark,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: backgroundGrey,
        outline: border,
      ),
      
      // Scaffold background (soft, luxury feel)
      scaffoldBackgroundColor: backgroundLight,
      
      // AppBar Theme (elegant, minimal)
      appBarTheme: AppBarTheme(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
          size: 24,
        ),
      ),
      
      // Card Theme (elegant, spacious)
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: Colors.black.withValues(alpha: 0.04), // Very subtle shadow
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
        ),
        color: surface,
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), // Generous spacing
        surfaceTintColor: Colors.transparent,
      ),
      
      // Button Themes (elegant, modern)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: primaryBlue.withValues(alpha: 0.2), // Soft colored shadow
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), // Generous padding
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), // Unified radius
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3, // Increased for premium look
          ),
        ).copyWith(
          elevation: WidgetStateProperty.resolveWith<double>(
            (Set<WidgetState> states) {
              if (states.contains(WidgetState.pressed)) return 0;
              if (states.contains(WidgetState.disabled)) return 0;
              return 1; // Very subtle elevation
            },
          ),
        ),
      ),
      
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryBlue,
          side: const BorderSide(color: primaryBlue, width: 1), // Subtle border
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16), // Generous padding
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), // Unified radius
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3, // Increased for premium look
          ),
        ),
      ),
      
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primaryBlue,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), // Generous padding
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), // Unified radius
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3, // Increased for premium look
          ),
        ),
      ),
      
      // Input Decoration Theme (elegant, spacious)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: backgroundGrey,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
          borderSide: const BorderSide(color: border, width: 1), // Subtle border
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
          borderSide: const BorderSide(color: border, width: 1), // Subtle border
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
          borderSide: const BorderSide(color: primaryBlue, width: 1), // Subtle focus border
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
          borderSide: const BorderSide(color: error, width: 1), // Subtle border
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
          borderSide: const BorderSide(color: error, width: 1), // Subtle border
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18), // Generous padding
      ),
      
      // Typography (Inter font - modern, clean)
      textTheme: textTheme.copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 57,
          fontWeight: FontWeight.w300,
          letterSpacing: -0.25,
          color: textPrimary,
          height: 1.2,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 45,
          fontWeight: FontWeight.w300,
          letterSpacing: 0,
          color: textPrimary,
          height: 1.2,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 36,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: textPrimary,
          height: 1.3,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 32,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3, // Increased for premium look
          color: textPrimary,
          height: 1.3,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3, // Increased for premium look
          color: textPrimary,
          height: 1.3,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1, // Increased for premium look
          color: textPrimary,
          height: 1.4,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1, // Increased for premium look
          color: textPrimary,
          height: 1.4,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.25, // Increased for premium look
          color: textPrimary,
          height: 1.5,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textPrimary,
          height: 1.5,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: textPrimary,
          height: 1.6,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.25,
          color: textPrimary,
          height: 1.6,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.4,
          color: textSecondary,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textPrimary,
          height: 1.4,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: textPrimary,
          height: 1.4,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: textSecondary,
          height: 1.3,
        ),
      ),
      
      // Divider Theme (subtle, elegant)
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      
      // Icon Theme
      iconTheme: const IconThemeData(
        color: textPrimary,
        size: 24,
      ),
      
      // List Tile Theme (spacious, elegant)
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
        ),
      ),
      
      // Chip Theme (elegant tags)
      chipTheme: ChipThemeData(
        backgroundColor: backgroundGrey,
        selectedColor: primaryBlue,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), // Unified radius
        ),
      ),
    );
  }
}
