import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_inspector_panel.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
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
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        filteredTranslationRowsProvider('p', 'fr')
            .overrideWith((_) async => [_row('1')]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Select a unit'), findsOneWidget);
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
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unit'), findsOneWidget);
    expect(find.textContaining('agent_actions_localised'), findsOneWidget);
    expect(find.textContaining('Use the Skald'), findsOneWidget);
    expect(find.textContaining('Utilise le Savoir'), findsOneWidget);
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
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 units selected'), findsOneWidget);
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
    'dirty target text auto-saves for previous unit when selection switches',
    (tester) async {
      final saves = <MapEntry<String, String>>[];
      final container = ProviderContainer(overrides: [
        filteredTranslationRowsProvider('p', 'fr')
            .overrideWith((_) async => [_row('1'), _row('2')]),
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
              onSave: (id, text) => saves.add(MapEntry(id, text)),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Type something into unit 1's target without blurring.
      final field = find.byKey(const Key('editor-inspector-target-field'));
      await tester.tap(field);
      await tester.enterText(field, 'Draft unit 1 text');

      // Switch selection to unit 2 — this must flush unit 1's dirty text first.
      container.read(editorSelectionProvider.notifier)
        ..clearSelection()
        ..toggleSelection('2');
      await tester.pumpAndSettle();

      expect(
        saves.any((e) => e.key == '1' && e.value == 'Draft unit 1 text'),
        isTrue,
        reason: 'Expected an auto-save for unit 1 with the typed text, '
            'got: $saves',
      );
    },
  );

  testWidgets(
    'single-selection body lays out without overflow at panel height',
    (tester) async {
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
      ]);
      addTearDown(container.dispose);
      container.read(editorSelectionProvider.notifier).toggleSelection('1');

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: SizedBox(
              height: 600,
              child: EditorInspectorPanel(
                projectId: 'p',
                languageId: 'fr',
                onSave: (_, _) {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Responsive layout with Expanded children must not overflow even at
      // constrained heights.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
      'shows Validation Issues section with Accept/Reject/Edit for needsReview row',
      (tester) async {
    TranslationRow needsReviewRow() {
      final unit = TranslationUnit(
        id: '1',
        projectId: 'p',
        key: 'k',
        sourceText: 'source',
        createdAt: 0,
        updatedAt: 0,
      );
      final version = TranslationVersion(
        id: '1-v',
        unitId: '1',
        projectLanguageId: 'pl',
        translatedText: 'dst',
        status: TranslationVersionStatus.needsReview,
        translationSource: TranslationSource.manual,
        validationIssues:
            '[{"rule":"variables","severity":"error","message":"missing %s"}]',
        createdAt: 0,
        updatedAt: 0,
      );
      return TranslationRow(unit: unit, version: version);
    }

    var accepted = false;
    var rejected = false;
    var edited = false;

    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [needsReviewRow()]),
      currentProjectProvider('p').overrideWith(
        (_) async => Project(
          id: 'p',
          name: 'p',
          gameInstallationId: 'g',
          projectType: 'mod',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      currentLanguageProvider('fr').overrideWith(
        (_) async => const Language(
            id: 'fr', code: 'fr', name: 'French', nativeName: 'Francais'),
      ),
    ]);
    addTearDown(container.dispose);

    // Single-select the needsReview row.
    container.read(editorSelectionProvider.notifier).toggleSelection('1');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 1080,
            child: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (_, _) {},
              onAcceptIssue: (_) => accepted = true,
              onRejectIssue: (_) => rejected = true,
              onEditIssue: (_) => edited = true,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('missing %s'), findsOneWidget);
    await tester.tap(find.text('Accept'));
    expect(accepted, isTrue);
    await tester.tap(find.text('Reject'));
    expect(rejected, isTrue);
    await tester.tap(find.text('Edit'));
    expect(edited, isTrue);
  });

  testWidgets('hides Validation Issues section for translated rows',
      (tester) async {
    TranslationRow translatedRow() {
      final unit = TranslationUnit(
        id: '2',
        projectId: 'p',
        key: 'k2',
        sourceText: 's',
        createdAt: 0,
        updatedAt: 0,
      );
      final version = TranslationVersion(
        id: '2-v',
        unitId: '2',
        projectLanguageId: 'pl',
        translatedText: 't',
        status: TranslationVersionStatus.translated,
        translationSource: TranslationSource.manual,
        createdAt: 0,
        updatedAt: 0,
      );
      return TranslationRow(unit: unit, version: version);
    }

    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [translatedRow()]),
      currentProjectProvider('p').overrideWith(
        (_) async => Project(
          id: 'p',
          name: 'p',
          gameInstallationId: 'g',
          projectType: 'mod',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      currentLanguageProvider('fr').overrideWith(
        (_) async => const Language(
            id: 'fr', code: 'fr', name: 'French', nativeName: 'Francais'),
      ),
    ]);
    addTearDown(container.dispose);
    container.read(editorSelectionProvider.notifier).toggleSelection('2');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 1080,
            child: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (_, _) {},
              onAcceptIssue: (_) {},
              onRejectIssue: (_) {},
              onEditIssue: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('VALIDATION ISSUES'), findsNothing);
  });

  testWidgets(
      'hides Validation Issues section when needsReview row has no issues JSON',
      (tester) async {
    TranslationRow row() {
      final unit = TranslationUnit(
        id: '3',
        projectId: 'p',
        key: 'k3',
        sourceText: 's',
        createdAt: 0,
        updatedAt: 0,
      );
      final version = TranslationVersion(
        id: '3-v',
        unitId: '3',
        projectLanguageId: 'pl',
        translatedText: 't',
        status: TranslationVersionStatus.needsReview,
        translationSource: TranslationSource.manual,
        // validationIssues left null — the defensive guard must hide the
        // section even though the row status is needsReview.
        createdAt: 0,
        updatedAt: 0,
      );
      return TranslationRow(unit: unit, version: version);
    }

    final container = ProviderContainer(overrides: [
      filteredTranslationRowsProvider('p', 'fr')
          .overrideWith((_) async => [row()]),
      currentProjectProvider('p').overrideWith(
        (_) async => Project(
          id: 'p',
          name: 'p',
          gameInstallationId: 'g',
          projectType: 'mod',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      currentLanguageProvider('fr').overrideWith(
        (_) async => const Language(
            id: 'fr', code: 'fr', name: 'French', nativeName: 'Francais'),
      ),
    ]);
    addTearDown(container.dispose);
    container.read(editorSelectionProvider.notifier).toggleSelection('3');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1920,
            height: 1080,
            child: EditorInspectorPanel(
              projectId: 'p',
              languageId: 'fr',
              onSave: (_, _) {},
              onAcceptIssue: (_) {},
              onRejectIssue: (_) {},
              onEditIssue: (_) {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('VALIDATION ISSUES'), findsNothing);
  });
}
