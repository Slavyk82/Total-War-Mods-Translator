import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_inspector_panel.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/validation/models/validation_issue.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';
import '../../../helpers/test_bootstrap.dart';

TranslationRow _row(String id) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'agent_actions_localised_description',
    sourceText: "Use the Skald's Knowledge to increase morale.",
    sourceLocFile: 'scm_norsca_skald.loc',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: 'Utilise le Savoir du Skald.',
    status: TranslationVersionStatus.translated,
    translationSource: TranslationSource.tmExact,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

TmMatch _suggestion({
  required String entryId,
  required String targetText,
  double similarity = 1.0,
  TmMatchType type = TmMatchType.exact,
}) {
  return TmMatch(
    entryId: entryId,
    sourceText: 'src',
    targetText: targetText,
    targetLanguageCode: 'fr',
    similarityScore: similarity,
    matchType: type,
    breakdown: const SimilarityBreakdown(
      levenshteinScore: 1.0,
      jaroWinklerScore: 1.0,
      tokenScore: 1.0,
      contextBoost: 0.0,
      weights: ScoreWeights.defaultWeights,
    ),
    usageCount: 3,
    lastUsedAt: DateTime.utc(2024, 1, 1),
  );
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1920, 1080);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('shows empty state when no row is selected', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: EditorInspectorPanel(
          projectId: 'p',
          languageId: 'fr',
          onSave: (_, _) {},
          onApplySuggestion: (_, _) {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        filteredTranslationRowsProvider('p', 'fr')
            .overrideWith((_) async => [_row('1')]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Sélectionnez une unité'), findsOneWidget);
  });

  testWidgets('shows full inspector for single selection', (tester) async {
    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [_row('1')]),
      currentProjectProvider('p').overrideWith((_) async => const Project(
            id: 'p',
            name: 'p',
            gameInstallationId: 'g',
            sourceLanguageCode: 'en',
            createdAt: 0,
            updatedAt: 0,
          )),
      currentLanguageProvider('fr').overrideWith((_) async => const Language(
            id: 'fr',
            code: 'fr',
            name: 'French',
            nativeName: 'Français',
          )),
      tmSuggestionsForUnitProvider('1', 'en', 'fr').overrideWith((_) async => [
            _suggestion(entryId: 'e1', targetText: 'Suggestion alpha'),
          ]),
    ]);
    addTearDown(container.dispose);
    container.read(editorSelectionProvider.notifier).toggleSelection('1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: EditorInspectorPanel(
            projectId: 'p',
            languageId: 'fr',
            onSave: (_, _) {},
            onApplySuggestion: (_, _) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unité'), findsOneWidget);
    expect(find.textContaining('agent_actions_localised'), findsOneWidget);
    expect(find.textContaining('Use the Skald'), findsOneWidget);
    expect(find.textContaining('Utilise le Savoir'), findsOneWidget);
    expect(find.textContaining('Suggestion alpha'), findsOneWidget);
  });

  testWidgets('shows multi-select header for N>1', (tester) async {
    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [_row('1'), _row('2')]),
    ]);
    addTearDown(container.dispose);
    container.read(editorSelectionProvider.notifier).toggleSelection('1');
    container.read(editorSelectionProvider.notifier).toggleSelection('2');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: EditorInspectorPanel(
            projectId: 'p',
            languageId: 'fr',
            onSave: (_, _) {},
            onApplySuggestion: (_, _) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 unités sélectionnées'), findsOneWidget);
  });

  testWidgets('target field calls onSave when focus is lost', (tester) async {
    String? savedUnit;
    String? savedText;
    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [_row('1')]),
      currentProjectProvider('p').overrideWith((_) async => const Project(
            id: 'p',
            name: 'p',
            gameInstallationId: 'g',
            sourceLanguageCode: 'en',
            createdAt: 0,
            updatedAt: 0,
          )),
      currentLanguageProvider('fr').overrideWith((_) async => const Language(
            id: 'fr',
            code: 'fr',
            name: 'French',
            nativeName: 'Français',
          )),
      tmSuggestionsForUnitProvider('1', 'en', 'fr')
          .overrideWith((_) async => []),
    ]);
    addTearDown(container.dispose);
    container.read(editorSelectionProvider.notifier).toggleSelection('1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: EditorInspectorPanel(
            projectId: 'p',
            languageId: 'fr',
            onSave: (id, text) {
              savedUnit = id;
              savedText = text;
            },
            onApplySuggestion: (_, _) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('editor-inspector-target-field'));
    await tester.tap(field);
    await tester.enterText(field, 'Nouveau texte');
    // Blur the field to trigger save-on-focus-loss.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    expect(savedUnit, '1');
    expect(savedText, 'Nouveau texte');
  });

  testWidgets(
    'renders inspector with validation issues without overflow',
    (tester) async {
      final row = _row('1');
      final issues = <ValidationIssue>[
        const ValidationIssue(
          type: ValidationIssueType.lengthDifference,
          severity: ValidationSeverity.warning,
          description: 'Translation length differs significantly from source',
          suggestion: 'Review the translation for completeness',
        ),
        const ValidationIssue(
          type: ValidationIssueType.punctuationMismatch,
          severity: ValidationSeverity.error,
          description: 'Final punctuation differs from source',
          suggestion: 'Add missing period at end',
          autoFixable: true,
          autoFixValue: 'Utilise le Savoir du Skald.',
        ),
      ];
      final container = ProviderContainer(overrides: [
        filteredTranslationRowsProvider('p', 'fr')
            .overrideWith((_) async => [row]),
        currentProjectProvider('p').overrideWith((_) async => const Project(
              id: 'p',
              name: 'p',
              gameInstallationId: 'g',
              sourceLanguageCode: 'en',
              createdAt: 0,
              updatedAt: 0,
            )),
        currentLanguageProvider('fr').overrideWith((_) async => const Language(
              id: 'fr',
              code: 'fr',
              name: 'French',
              nativeName: 'Français',
            )),
        tmSuggestionsForUnitProvider('1', 'en', 'fr')
            .overrideWith((_) async => []),
        validationIssuesProvider(row.sourceText, row.translatedText!)
            .overrideWith((_) async => issues),
      ]);
      addTearDown(container.dispose);
      container.read(editorSelectionProvider.notifier).toggleSelection('1');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (_, _) {},
              onApplySuggestion: (_, _) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Regression: when the panel hosts a non-empty validation list it must
      // not blow up with a layout-bounds assertion (Expanded inside an
      // unbounded SingleChildScrollView).
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Validation Issues Found'), findsOneWidget);
    },
  );
}
