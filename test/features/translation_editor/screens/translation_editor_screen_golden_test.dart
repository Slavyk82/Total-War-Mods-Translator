import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/llm_custom_rules_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/providers/editor_row_models.dart';
import 'package:twmt/features/translation_editor/providers/grid_data_providers.dart';
import 'package:twmt/features/translation_editor/providers/llm_model_providers.dart';
import 'package:twmt/features/translation_editor/providers/tm_reuse_stats_provider.dart';
import 'package:twmt/features/translation_editor/providers/tm_suggestions_provider.dart';
import 'package:twmt/features/translation_editor/providers/translation_settings_provider.dart';
import 'package:twmt/features/translation_editor/screens/translation_editor_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Build N populated translation rows with deterministic ids/keys/text so the
/// golden output is byte-stable across runs.
List<TranslationRow> _buildRows(int n) => List.generate(n, (i) {
      final unit = TranslationUnit(
        id: 'u$i',
        projectId: 'p',
        key: 'agent_actions_$i',
        sourceText: 'Source text $i goes here.',
        sourceLocFile: 'scm_norsca_skald.loc',
        createdAt: 0,
        updatedAt: 0,
      );
      final version = TranslationVersion(
        id: 'v$i',
        unitId: 'u$i',
        projectLanguageId: 'pl',
        translatedText: 'Texte cible $i ici.',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.tmExact,
        createdAt: 0,
        updatedAt: 0,
      );
      return TranslationRow(unit: unit, version: version);
    });

/// Minimal project fixture that exposes the fields read by EditorTopBar's
/// crumb (`name`) and the inspector's source-language fallback.
Project _project() => Project(
      id: 'p',
      name: 'Test Mod Project',
      gameInstallationId: 'install-test',
      createdAt: 0,
      updatedAt: 0,
    );

Language _language() => const Language(
      id: 'fr',
      code: 'fr',
      name: 'French',
      nativeName: 'Français',
    );

Future<void> _golden(
  WidgetTester tester,
  String name,
  ThemeData theme, {
  required bool populated,
}) async {
  // Match the spec mockup viewport. The teardown returns the surface to the
  // default test size so subsequent tests run unaffected.
  await tester.binding.setSurfaceSize(const Size(1920, 1080));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final rows = populated ? _buildRows(20) : <TranslationRow>[];
  final translatedCount = rows
      .where((r) => r.status == TranslationVersionStatus.translated)
      .length;

  await tester.pumpWidget(createThemedTestableWidget(
    const TranslationEditorScreen(projectId: 'p', languageId: 'fr'),
    theme: theme,
    overrides: <Override>[
      currentProjectProvider('p').overrideWith((_) async => _project()),
      currentLanguageProvider('fr').overrideWith((_) async => _language()),
      translationRowsProvider('p', 'fr').overrideWith((_) async => rows),
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => rows),
      editorStatsProvider('p', 'fr').overrideWith((_) async => EditorStats(
            totalUnits: rows.length,
            translatedCount: translatedCount,
            pendingCount: 0,
            needsReviewCount: 0,
            completionPercentage: rows.isEmpty ? 0 : 100,
          )),
      tmReuseStatsProvider('p', 'fr').overrideWith((_) async => TmReuseStats(
            translatedCount: translatedCount,
            reusedCount: translatedCount,
            reusePercentage: rows.isEmpty ? 0 : 100,
          )),
      // The inspector renders the empty state when no row is selected, so the
      // suggestion family is normally not read; override defensively in case
      // any downstream widget warms it up.
      tmSuggestionsForUnitProvider('u0', 'en', 'fr')
          .overrideWith((_) async => const <TmMatch>[]),
      // Selected LLM model: keep null so the toolbar shows its placeholder.
      selectedLlmModelProvider.overrideWithValue(null),
      availableLlmModelsProvider.overrideWith((_) async => const []),
      // Mod-rule chip: stub the project-rule lookup to avoid hitting the
      // settings repository.
      hasProjectRuleProvider('p').overrideWith((_) async => false),
      // Translation settings: avoid touching the real database.
      translationSettingsProvider.overrideWith(
        () => _StubTranslationSettingsNotifier(),
      ),
    ],
  ));
  await tester.pumpAndSettle();

  await expectLater(
    find.byType(TranslationEditorScreen),
    matchesGoldenFile('../goldens/$name.png'),
  );
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  testWidgets('atelier populated', (tester) async {
    await _golden(
      tester,
      'editor_atelier_populated',
      AppTheme.atelierDarkTheme,
      populated: true,
    );
  });

  testWidgets('atelier empty', (tester) async {
    await _golden(
      tester,
      'editor_atelier_empty_selection',
      AppTheme.atelierDarkTheme,
      populated: false,
    );
  });

  testWidgets('forge populated', (tester) async {
    await _golden(
      tester,
      'editor_forge_populated',
      AppTheme.forgeDarkTheme,
      populated: true,
    );
  });

  testWidgets('forge empty', (tester) async {
    await _golden(
      tester,
      'editor_forge_empty_selection',
      AppTheme.forgeDarkTheme,
      populated: false,
    );
  });
}

/// Stand-in for the translation settings notifier so the editor screen's
/// `setSkipTranslationMemory(false)` post-frame callback is a no-op rather
/// than hitting the real database.
class _StubTranslationSettingsNotifier extends TranslationSettingsNotifier {
  @override
  TranslationSettings build() => const TranslationSettings(
        unitsPerBatch: 0,
        parallelBatches: 5,
        skipTranslationMemory: false,
      );

  @override
  void setSkipTranslationMemory(bool value) {}

  @override
  Future<void> updateSettings({
    required int unitsPerBatch,
    required int parallelBatches,
  }) async {}

  @override
  Future<TranslationSettings> ensureLoaded() async => state;
}
