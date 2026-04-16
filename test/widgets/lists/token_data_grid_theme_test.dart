import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

void main() {
  test('buildTokenDataGridTheme maps atelier tokens to SfDataGridThemeData', () {
    final atelier = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final theme = buildTokenDataGridTheme(atelier);
    expect(theme.headerColor, atelier.panel);
    expect(theme.gridLineColor, atelier.border);
    expect(theme.selectionColor, atelier.accentBg);
    expect(theme.rowHoverColor, atelier.panel2);
  });

  test('buildTokenDataGridTheme maps forge tokens', () {
    final forge = AppTheme.forgeDarkTheme.extension<TwmtThemeTokens>()!;
    final theme = buildTokenDataGridTheme(forge);
    expect(theme.headerColor, forge.panel);
    expect(theme.selectionColor, forge.accentBg);
  });
}
