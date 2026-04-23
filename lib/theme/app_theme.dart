import 'package:flutter/material.dart';
import 'package:twmt/theme/themed_scrollbar.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';
import 'package:twmt/theme/tokens/shogun_tokens.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/theme/tokens/vellum_tokens.dart';
import 'package:twmt/theme/tokens/warpstone_tokens.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

class AppTheme {
  /// Atelier dark theme — default after the UI redesign (plan 1).
  static ThemeData get atelierDarkTheme => _buildThemed(atelierTokens);

  /// Forge dark theme — technical variant.
  static ThemeData get forgeDarkTheme => _buildThemed(forgeTokens);

  /// Slate dark theme — sober cold monochrome with indigo accent.
  static ThemeData get slateDarkTheme => _buildThemed(slateTokens);

  /// Vellum light theme — the only light variant, cream paper + ink blue.
  static ThemeData get vellumLightTheme =>
      _buildThemed(vellumTokens, brightness: Brightness.light);

  /// Warpstone dark theme — Total War: Warhammer, violet + warpstone green.
  static ThemeData get warpstoneDarkTheme => _buildThemed(warpstoneTokens);

  /// Shogun dark theme — Total War: Shogun 2, lacquer black + vermillion.
  static ThemeData get shogunDarkTheme => _buildThemed(shogunTokens);

  /// Shared builder wiring a [TwmtThemeTokens] instance into a [ThemeData].
  ///
  /// Produces a Fluent-style theme whose surfaces, dividers and scrollbars
  /// all derive from the token palette. The default brightness is dark;
  /// pass [Brightness.light] for light-mode tokens (Vellum). Material
  /// component themes that are not yet redesigned (cards, ListTile, etc.)
  /// are left on minimal defaults; the per-screen redesigns in later plans
  /// will replace direct colour references with `context.tokens` lookups.
  static ThemeData _buildThemed(
    TwmtThemeTokens tokens, {
    Brightness brightness = Brightness.dark,
  }) {
    final colorScheme = brightness == Brightness.light
        ? ColorScheme.light(
            primary: tokens.accent,
            onPrimary: tokens.accentFg,
            secondary: tokens.accent,
            onSecondary: tokens.accentFg,
            surface: tokens.panel,
            onSurface: tokens.text,
            error: tokens.err,
            onError: tokens.accentFg,
          )
        : ColorScheme.dark(
            primary: tokens.accent,
            onPrimary: tokens.accentFg,
            secondary: tokens.accent,
            onSecondary: tokens.accentFg,
            surface: tokens.panel,
            onSurface: tokens.text,
            error: tokens.err,
            onError: tokens.accentFg,
          );

    return ThemeData(
      useMaterial3: false,
      brightness: brightness,
      extensions: <ThemeExtension<dynamic>>[tokens],
      colorScheme: colorScheme,
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
