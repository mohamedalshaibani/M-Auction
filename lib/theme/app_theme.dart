import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// M Auction Design System
/// Primary from logo dark tone; minimal secondary blue; white/light backgrounds
class AppTheme {
  // Primary brand color - used for buttons, active states, icons, key accents only
  static const Color primaryBlue = Color(0xFF006AA6);

  // Minimal light blue - only for subtle backgrounds / disabled / secondary UI
  static const Color primaryLight = Color(0xFFE8EEF4);

  // Header logo - consistent size; use logo_light on dark header
  static const double headerLogoWidth = 112;
  static const double headerLogoHeight = 60;
  static const String logoAssetLight = 'assets/branding/logo_light.png';
  static const String logoAssetSource = 'assets/branding/logo_source.png';

  // Backgrounds - white and very light grey (clean, premium)
  static const Color backgroundLight = Color(0xFFFAFAFA);
  static const Color backgroundGrey = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceElevated = Color(0xFFFFFFFF);

  // Text colors
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary = Color(0xFF9CA3AF);
  static const Color textDisabled = Color(0xFFBDBDBD);

  // Semantic colors
  static const Color success = Color(0xFF2E7D32);
  static const Color error = Color(0xFFC62828);
  static const Color warning = Color(0xFFF57C00);
  static const Color info = Color(0xFF006AA6); // Same as primary

  // Borders and dividers - soft grey
  static const Color border = Color(0xFFE5E7EB);
  static const Color divider = Color(0xFFE5E7EB);

  /// Get the app theme
  static ThemeData get lightTheme {
    // Inter font family for modern, clean typography
    final textTheme = GoogleFonts.interTextTheme();
    
    return ThemeData(
      useMaterial3: true,
      
      // Color Scheme - primary from logo dark; minimal secondary blue
      colorScheme: ColorScheme.light(
        primary: primaryBlue,
        onPrimary: Colors.white,
        primaryContainer: primaryLight,
        onPrimaryContainer: textPrimary,
        secondary: textSecondary,
        onSecondary: Colors.white,
        secondaryContainer: backgroundGrey,
        onSecondaryContainer: textPrimary,
        error: error,
        onError: Colors.white,
        surface: surface,
        onSurface: textPrimary,
        surfaceContainerHighest: backgroundGrey,
        outline: border,
      ),
      
      // Scaffold background (soft, luxury feel)
      scaffoldBackgroundColor: backgroundLight,
      
      // AppBar Theme - white header, dark text and icons
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: textPrimary,
          letterSpacing: -0.5,
        ),
        iconTheme: const IconThemeData(
          color: textPrimary,
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
      
      // Button Themes - same dark blue for primary actions
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.black.withValues(alpha: 0.08),
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
      
      // Typography (Inter font - refined, slightly smaller hierarchy)
      textTheme: textTheme.copyWith(
        displayLarge: GoogleFonts.inter(
          fontSize: 48,
          fontWeight: FontWeight.w300,
          letterSpacing: -0.25,
          color: textPrimary,
          height: 1.2,
        ),
        displayMedium: GoogleFonts.inter(
          fontSize: 38,
          fontWeight: FontWeight.w300,
          letterSpacing: 0,
          color: textPrimary,
          height: 1.2,
        ),
        displaySmall: GoogleFonts.inter(
          fontSize: 30,
          fontWeight: FontWeight.w400,
          letterSpacing: 0,
          color: textPrimary,
          height: 1.3,
        ),
        headlineLarge: GoogleFonts.inter(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: textPrimary,
          height: 1.3,
        ),
        headlineMedium: GoogleFonts.inter(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: textPrimary,
          height: 1.3,
        ),
        headlineSmall: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textPrimary,
          height: 1.4,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textPrimary,
          height: 1.4,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: textPrimary,
          height: 1.5,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textPrimary,
          height: 1.5,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.15,
          color: textPrimary,
          height: 1.5,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.2,
          color: textPrimary,
          height: 1.5,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w400,
          letterSpacing: 0.35,
          color: textSecondary,
          height: 1.5,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.1,
          color: textPrimary,
          height: 1.4,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
          color: textPrimary,
          height: 1.4,
        ),
        labelSmall: GoogleFonts.inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
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
