// Golden tests for the Settings screen - General tab (Plan 5e - Task 8).
//
// The General tab renders four sections: LanguagePreferences, a collapsed
// IgnoredSourceTexts accordion (whose badge reads
// `enabledIgnoredTextsCountProvider`), MaintenanceSection, and BackupSection.
// We override the async providers so every `.when(data: ...)` branch
// resolves immediately and none of the nested widgets flashes a spinner.
// `maintenanceStateProvider` / `backupStateProvider` are synchronous
// Notifiers whose default state already renders the idle UI, so they need
// no override.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/ignored_source_texts_providers.dart';
import 'package:twmt/features/settings/providers/language_settings_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Deterministic `generalSettingsProvider` state — an empty map is enough
/// because the General tab only gates its body on the `data:` branch; it
/// doesn't read specific keys (those are read by the Folders tab).
class _FakeGeneralSettings extends GeneralSettings {
  @override
  Future<Map<String, String>> build() async => const <String, String>{};
}

/// Two canonical languages so the language data grid has stable rows.
class _FakeLanguageSettings extends LanguageSettings {
  @override
  Future<LanguageSettingsState> build() async => const LanguageSettingsState(
        languages: [
          Language(
            id: 'lang-en',
            code: 'en',
            name: 'English',
            nativeName: 'English',
            isActive: true,
            isCustom: false,
          ),
          Language(
            id: 'lang-fr',
            code: 'fr',
            name: 'French',
            nativeName: 'Français',
            isActive: true,
            isCustom: false,
          ),
        ],
        defaultLanguageCode: 'fr',
      );
}

/// Empty ignored list so the accordion's body would be empty when expanded;
/// still required to prevent the datagrid from throwing during build.
class _FakeIgnoredSourceTexts extends IgnoredSourceTexts {
  @override
  Future<List<IgnoredSourceText>> build() async => const <IgnoredSourceText>[];
}

List<Override> _overrides() => [
      generalSettingsProvider.overrideWith(_FakeGeneralSettings.new),
      languageSettingsProvider.overrideWith(_FakeLanguageSettings.new),
      ignoredSourceTextsProvider.overrideWith(_FakeIgnoredSourceTexts.new),
      enabledIgnoredTextsCountProvider.overrideWith((_) async => 0),
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
    // General is the default tab (index 0) — no navigation needed.
  }

  testWidgets('settings general atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_general_atelier.png'),
    );
  });

  testWidgets('settings general forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_general_forge.png'),
    );
  });
}
