import 'package:flutter/material.dart';
import 'package:twmt/theme/themed_scrollbar.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

class AppTheme {
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
