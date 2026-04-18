// Golden tests for the Settings screen - Appearance tab (Plan 5e - Task 8).
//
// The Appearance tab only reads `themeNameProvider` to decide which palette
// card is highlighted. We override that provider to pin the active palette
// to match the theme under test, so the goldens are deterministic across
// both Atelier and Forge.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/providers/theme_name_provider.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Minimal fake that pins the active palette to a deterministic value and
/// skips the SharedPreferences load performed by the real notifier.
class _FakeThemeNameNotifier extends ThemeNameNotifier {
  _FakeThemeNameNotifier(this._active);

  final TwmtThemeName _active;

  @override
  Future<TwmtThemeName> build() async => _active;
}

List<Override> _overrides(TwmtThemeName active) => [
      themeNameProvider.overrideWith(() => _FakeThemeNameNotifier(active)),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    TwmtThemeName active,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SettingsScreen(),
      theme: theme,
      overrides: _overrides(active),
    ));
    await tester.pumpAndSettle();

    // Appearance is the 4th tab (index 3) — switch to it before capturing.
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings appearance atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme, TwmtThemeName.atelier);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_appearance_atelier.png'),
    );
  });

  testWidgets('settings appearance forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme, TwmtThemeName.forge);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_appearance_forge.png'),
    );
  });
}
