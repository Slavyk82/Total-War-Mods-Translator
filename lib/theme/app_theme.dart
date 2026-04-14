import 'package:flutter/material.dart';
import 'package:twmt/theme/themed_scrollbar.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

class AppTheme {
  static const _primaryColor = Color(0xFF0078D4);
  static const _secondaryColor = Color(0xFF106EBE);
  static const _surfaceColor = Color(0xFFF3F3F3);
  static const _backgroundColor = Color(0xFFFFFFFF);
  static const _dividerColor = Color(0xFFE1E1E1);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: false, // Using Fluent Design, not Material 3
      colorScheme: ColorScheme.light(
        primary: _primaryColor,
        secondary: _secondaryColor,
        surface: _surfaceColor,
        primaryContainer: const Color(0xFFD6E8FF),
        onPrimaryContainer: const Color(0xFF001D36),
        secondaryContainer: const Color(0xFFD1E4F4),
        onSecondaryContainer: const Color(0xFF0A1E29),
        tertiaryContainer: const Color(0xFFE8DEF8),
        onTertiaryContainer: const Color(0xFF1D192B),
      ),
      scaffoldBackgroundColor: _backgroundColor,
      dividerColor: _dividerColor,
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: _dividerColor, width: 1),
        ),
        color: _backgroundColor,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      iconTheme: const IconThemeData(
        size: 20,
        color: Color(0xFF605E5C),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: Color(0xFF323130),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF323130),
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFF323130),
        ),
        bodyMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFF605E5C),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: false, // Using Fluent Design, not Material 3
      colorScheme: const ColorScheme.dark(
        primary: _primaryColor,
        secondary: _secondaryColor,
        surface: Color(0xFF252525),
        primaryContainer: Color(0xFF004578),
        onPrimaryContainer: Color(0xFFD6E8FF),
        secondaryContainer: Color(0xFF2D4A5E),
        onSecondaryContainer: Color(0xFFD1E4F4),
        tertiaryContainer: Color(0xFF4A3B5C),
        onTertiaryContainer: Color(0xFFE8DEF8),
      ),
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      dividerColor: const Color(0xFF3B3B3B),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: const BorderSide(color: Color(0xFF3B3B3B), width: 1),
        ),
        color: const Color(0xFF252525),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      iconTheme: const IconThemeData(
        size: 20,
        color: Color(0xFFB3B3B3),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: Color(0xFFF3F3F3),
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE1E1E1),
        ),
        bodyLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: Color(0xFFE1E1E1),
        ),
        bodyMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: Color(0xFFA19F9D),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  /// Atelier dark theme — default after the UI redesign (plan 1).
  static ThemeData get atelierDarkTheme => _buildThemedDark(atelierTokens);

  /// Forge dark theme — technical variant.
  static ThemeData get forgeDarkTheme => _buildThemedDark(forgeTokens);

  /// Shared builder wiring a [TwmtThemeTokens] instance into a [ThemeData].
  ///
  /// Produces a Fluent-style dark theme whose surfaces, dividers and
  /// scrollbars all derive from the token palette. Material component
  /// themes that are not yet redesigned (cards, ListTile, etc.) are left
  /// on minimal defaults; the per-screen redesigns in later plans will
  /// replace direct colour references with `context.tokens` lookups.
  static ThemeData _buildThemedDark(TwmtThemeTokens tokens) {
    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      extensions: <ThemeExtension<dynamic>>[tokens],
      colorScheme: ColorScheme.dark(
        primary: tokens.accent,
        onPrimary: tokens.accentFg,
        secondary: tokens.accent,
        onSecondary: tokens.accentFg,
        surface: tokens.panel,
        onSurface: tokens.text,
        error: tokens.err,
        onError: tokens.accentFg,
      ),
      scaffoldBackgroundColor: tokens.bg,
      dividerColor: tokens.border,
      scrollbarTheme: themedScrollbar(tokens),
      textTheme: TextTheme(
        headlineLarge: tokens.fontDisplay.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w400,
          color: tokens.text,
        ),
        headlineMedium: tokens.fontDisplay.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w500,
          color: tokens.text,
        ),
        bodyLarge: tokens.fontBody.copyWith(
          fontSize: 14,
          color: tokens.text,
        ),
        bodyMedium: tokens.fontBody.copyWith(
          fontSize: 13,
          color: tokens.textMid,
        ),
        bodySmall: tokens.fontBody.copyWith(
          fontSize: 12,
          color: tokens.textDim,
        ),
      ),
      iconTheme: IconThemeData(color: tokens.textMid, size: 20),
    );
  }
}
