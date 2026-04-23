import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';
import 'package:twmt/theme/tokens/shogun_tokens.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';
import 'package:twmt/theme/tokens/vellum_tokens.dart';
import 'package:twmt/theme/tokens/warpstone_tokens.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

void main() {
  group('AppTheme', () {
    test('atelierDarkTheme carries atelier tokens', () {
      final theme = AppTheme.atelierDarkTheme;
      final tokens = theme.extension<TwmtThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.accent, atelierTokens.accent);
      expect(tokens.bg, atelierTokens.bg);
    });

    test('forgeDarkTheme carries forge tokens', () {
      final theme = AppTheme.forgeDarkTheme;
      final tokens = theme.extension<TwmtThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.accent, forgeTokens.accent);
      expect(tokens.bg, forgeTokens.bg);
    });

    test('slateDarkTheme carries slate tokens', () {
      final theme = AppTheme.slateDarkTheme;
      final tokens = theme.extension<TwmtThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.accent, slateTokens.accent);
      expect(tokens.bg, slateTokens.bg);
    });

    test('warpstoneDarkTheme carries warpstone tokens', () {
      final theme = AppTheme.warpstoneDarkTheme;
      final tokens = theme.extension<TwmtThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.accent, warpstoneTokens.accent);
      expect(tokens.bg, warpstoneTokens.bg);
    });

    test('shogunDarkTheme carries shogun tokens', () {
      final theme = AppTheme.shogunDarkTheme;
      final tokens = theme.extension<TwmtThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.accent, shogunTokens.accent);
      expect(tokens.bg, shogunTokens.bg);
    });

    test('vellumLightTheme carries vellum tokens and light brightness', () {
      final theme = AppTheme.vellumLightTheme;
      final tokens = theme.extension<TwmtThemeTokens>();
      expect(tokens, isNotNull);
      expect(tokens!.accent, vellumTokens.accent);
      expect(tokens.bg, vellumTokens.bg);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
    });

    test('all dark themes report Brightness.dark', () {
      final darkThemes = <ThemeData>[
        AppTheme.atelierDarkTheme,
        AppTheme.forgeDarkTheme,
        AppTheme.slateDarkTheme,
        AppTheme.warpstoneDarkTheme,
        AppTheme.shogunDarkTheme,
      ];
      for (final theme in darkThemes) {
        expect(theme.brightness, Brightness.dark);
      }
    });

    test('each theme paints scaffold background from its bg token', () {
      expect(AppTheme.atelierDarkTheme.scaffoldBackgroundColor,
          atelierTokens.bg);
      expect(AppTheme.forgeDarkTheme.scaffoldBackgroundColor, forgeTokens.bg);
      expect(AppTheme.slateDarkTheme.scaffoldBackgroundColor, slateTokens.bg);
      expect(AppTheme.vellumLightTheme.scaffoldBackgroundColor,
          vellumTokens.bg);
      expect(AppTheme.warpstoneDarkTheme.scaffoldBackgroundColor,
          warpstoneTokens.bg);
      expect(AppTheme.shogunDarkTheme.scaffoldBackgroundColor,
          shogunTokens.bg);
    });

    test('every theme configures a ScrollbarTheme (default thickness)', () {
      final themes = <ThemeData>[
        AppTheme.atelierDarkTheme,
        AppTheme.forgeDarkTheme,
        AppTheme.slateDarkTheme,
        AppTheme.vellumLightTheme,
        AppTheme.warpstoneDarkTheme,
        AppTheme.shogunDarkTheme,
      ];
      for (final theme in themes) {
        final sb = theme.scrollbarTheme;
        // thickness is intentionally unset to inherit Material's default.
        expect(sb.thickness, isNull);
        expect(sb.thumbVisibility?.resolve(const <WidgetState>{}), isTrue);
      }
    });
  });
}
