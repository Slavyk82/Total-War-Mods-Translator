import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/tokens/atelier_tokens.dart';
import 'package:twmt/theme/tokens/forge_tokens.dart';
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

    test('atelierDarkTheme scaffold background matches atelier bg', () {
      expect(AppTheme.atelierDarkTheme.scaffoldBackgroundColor,
          atelierTokens.bg);
    });

    test('forgeDarkTheme scaffold background matches forge bg', () {
      expect(AppTheme.forgeDarkTheme.scaffoldBackgroundColor, forgeTokens.bg);
    });

    test('both themes configure a ScrollbarTheme (default thickness)', () {
      for (final theme
          in [AppTheme.atelierDarkTheme, AppTheme.forgeDarkTheme]) {
        final sb = theme.scrollbarTheme;
        // thickness is intentionally unset to inherit Material's default.
        expect(sb.thickness, isNull);
        expect(sb.thumbVisibility?.resolve(const <WidgetState>{}), isTrue);
      }
    });

    test('lightTheme still exists and has no TwmtThemeTokens yet', () {
      // Light theme is deliberately left untouched in plan 1.
      final tokens = AppTheme.lightTheme.extension<TwmtThemeTokens>();
      expect(tokens, isNull);
    });
  });
}
