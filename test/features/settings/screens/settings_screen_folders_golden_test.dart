// Golden tests for the Settings screen - Folders tab (Plan 5e - Task 8).
//
// The Folders tab's root widget gates on `generalSettingsProvider` and only
// renders GameInstallations / Workshop / Rpfm sections once the map
// resolves. The nested sections read that same provider to seed their
// TextEditingControllers; we ship a minimal fixture with a couple of game
// paths populated so at least one FluentExpander starts expanded,
// exercising the populated branch of the golden.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Folders fixture: a pair of WH3/WH2 paths, a Workshop base, and an RPFM
/// binary path. The remaining game paths stay empty so their expanders
/// render collapsed.
class _FakeGeneralSettings extends GeneralSettings {
  @override
  Future<Map<String, String>> build() async => const <String, String>{
        SettingsKeys.gamePathWh3: r'C:\Games\Total War WARHAMMER III',
        SettingsKeys.gamePathWh2: r'C:\Games\Total War WARHAMMER II',
        SettingsKeys.gamePathWh: '',
        SettingsKeys.gamePathRome2: '',
        SettingsKeys.gamePathAttila: '',
        SettingsKeys.gamePathTroy: '',
        SettingsKeys.gamePath3k: '',
        SettingsKeys.gamePathPharaoh: '',
        SettingsKeys.gamePathPharaohDynasties: '',
        SettingsKeys.workshopPath: r'C:\Steam\steamapps\workshop\content',
        SettingsKeys.rpfmPath: r'C:\Tools\rpfm\rpfm_cli.exe',
        SettingsKeys.rpfmSchemaPath: r'C:\Tools\rpfm\schemas',
        SettingsKeys.defaultTargetLanguage: 'fr',
        SettingsKeys.autoUpdate: 'true',
      };
}

List<Override> _overrides() => [
      generalSettingsProvider.overrideWith(_FakeGeneralSettings.new),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SettingsScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await tester.pumpAndSettle();

    // Folders is the 2nd tab (index 1).
    await tester.tap(find.text('Folders'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings folders atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_folders_atelier.png'),
    );
  });

  testWidgets('settings folders forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_folders_forge.png'),
    );
  });
}
