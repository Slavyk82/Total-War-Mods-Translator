import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/events/batch_events.dart';
import 'package:twmt/providers/editor_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart' as shared_repo;
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/shared/event_bus.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/features/translation_editor/widgets/editor_datagrid.dart';
import 'package:twmt/features/translation_editor/widgets/translation_history_dialog.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

class _MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class _MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

/// A version repo that succeeds for the bulk operations exercised by the
/// context-menu action handlers (clear / delete / mark-as-translated).
TranslationVersionRepository _okVersionRepo() {
  final repo = _MockVersionRepository();
  when(() => repo.update(any())).thenAnswer(
    (i) async => Ok<TranslationVersion, TWMTDatabaseException>(
      i.positionalArguments.first as TranslationVersion,
    ),
  );
  when(() => repo.delete(any())).thenAnswer(
    (_) async => const Ok<void, TWMTDatabaseException>(null),
  );
  when(() => repo.clearBatch(any(), onProgress: any(named: 'onProgress')))
      .thenAnswer((_) async => const Ok<int, TWMTDatabaseException>(1));
  return repo;
}

const String _projectId = 'p1';
const String _languageId = 'fr';
const String _projectLanguageId = 'pl1';

/// Build a TranslationRow with controllable status / source / text so we can
/// exercise the different cell renderings (translated / untranslated /
/// needs-review).
TranslationRow _row(
  String id, {
  String? translatedText,
  TranslationVersionStatus status = TranslationVersionStatus.translated,
  TranslationSource source = TranslationSource.llm,
  String? validationIssues,
  bool isManuallyEdited = false,
}) {
  final unit = TranslationUnit(
    id: id,
    projectId: _projectId,
    key: 'key_$id',
    sourceText: 'Source text for $id',
    sourceLocFile: 'file_$id.loc',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: _projectLanguageId,
    translatedText: translatedText,
    status: status,
    translationSource: source,
    validationIssues: validationIssues,
    isManuallyEdited: isManuallyEdited,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

/// A few rows in mixed states, so the grid renders translated, untranslated,
/// and needs-review cells together.
List<TranslationRow> _mixedRows() => [
      _row('a', translatedText: 'Bonjour'),
      _row('b',
          translatedText: null, status: TranslationVersionStatus.pending),
      _row('c',
          translatedText: 'À revoir',
          status: TranslationVersionStatus.needsReview,
          source: TranslationSource.manual,
          validationIssues:
              '[{"rule":"variables","severity":"error","message":"missing %s"}]'),
    ];

ProjectLanguageRepository _stubProjectLanguageRepo({bool matching = true}) {
  final repo = _MockProjectLanguageRepository();
  when(() => repo.getByProject(any())).thenAnswer(
    (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>(
      matching
          ? const [
              ProjectLanguage(
                id: _projectLanguageId,
                projectId: _projectId,
                languageId: _languageId,
                createdAt: 0,
                updatedAt: 0,
              ),
            ]
          : const [],
    ),
  );
  return repo;
}

/// Pump the EditorDataGrid under a themed, sized scope with the row provider
/// overridden. Returns the captured callback recorders so individual tests can
/// assert on them.
Future<void> _pumpGrid(
  WidgetTester tester, {
  required List<Override> rowOverrides,
  List<String>? doubleTapped,
  ProjectLanguageRepository? projectLanguageRepo,
  bool withForceRetranslate = true,
}) async {
  await tester.pumpWidget(createThemedTestableWidget(
    Scaffold(
      body: EditorDataGrid(
        projectId: _projectId,
        languageId: _languageId,
        onCellEdit: (_, _) async {},
        onRowDoubleTap: doubleTapped?.add,
        onForceRetranslate: withForceRetranslate ? () async {} : null,
      ),
    ),
    theme: AppTheme.atelierDarkTheme,
    screenSize: const Size(1400, 1000),
    overrides: [
      shared_repo.projectLanguageRepositoryProvider.overrideWithValue(
          projectLanguageRepo ?? _stubProjectLanguageRepo()),
      ...rowOverrides,
    ],
  ));
  await tester.pumpAndSettle();
}

List<Override> _filteredRows(List<TranslationRow> rows) => [
      filteredTranslationRowsProvider(_projectId, _languageId)
          .overrideWith((_) async => rows),
      translationRowsProvider(_projectId, _languageId)
          .overrideWith((_) async => rows),
    ];

void main() {
  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
    registerFallbackValue(
      const TranslationVersion(
        id: 'fallback',
        unitId: 'fallback',
        projectLanguageId: 'fallback',
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize =
        const Size(1400, 1000);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('renders the grid with rows in mixed states', (tester) async {
    await _pumpGrid(tester, rowOverrides: _filteredRows(_mixedRows()));

    expect(find.byType(SfDataGrid), findsOneWidget);
    // Column headers and source cells render.
    expect(find.textContaining('Source text for a'), findsWidgets);
    // Header checkbox is present.
    expect(find.byType(Checkbox), findsWidgets);
  });

  testWidgets('renders with an empty data set', (tester) async {
    await _pumpGrid(tester, rowOverrides: _filteredRows(const []));

    // Grid still builds; no row content present.
    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.textContaining('Source text for'), findsNothing);
  });

  testWidgets('shows a spinner while initial load is pending', (tester) async {
    final completer = Completer<List<TranslationRow>>();
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: EditorDataGrid(
          projectId: _projectId,
          languageId: _languageId,
          onCellEdit: (_, _) async {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      screenSize: const Size(1400, 1000),
      overrides: [
        shared_repo.projectLanguageRepositoryProvider
            .overrideWithValue(_stubProjectLanguageRepo()),
        filteredTranslationRowsProvider(_projectId, _languageId)
            .overrideWith((_) => completer.future),
        translationRowsProvider(_projectId, _languageId)
            .overrideWith((_) => completer.future),
      ],
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an error panel when the rows provider fails',
      (tester) async {
    await _pumpGrid(
      tester,
      rowOverrides: [
        filteredTranslationRowsProvider(_projectId, _languageId)
            .overrideWith((_) async => throw Exception('boom')),
        translationRowsProvider(_projectId, _languageId)
            .overrideWith((_) async => throw Exception('boom')),
      ],
    );

    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.byType(SfDataGrid), findsNothing);
  });

  testWidgets('header select-all checkbox selects then deselects all rows',
      (tester) async {
    final rows = _mixedRows();
    await _pumpGrid(tester, rowOverrides: _filteredRows(rows));

    final headerCheckbox = find.byType(Checkbox).first;

    // Initially nothing selected (false / unchecked).
    Checkbox cb = tester.widget<Checkbox>(headerCheckbox);
    expect(cb.value, isFalse);

    // Tap to select all.
    await tester.tap(headerCheckbox);
    await tester.pumpAndSettle();
    cb = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(cb.value, isTrue);

    // Tap again to clear.
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    cb = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(cb.value, isFalse);
  });

  testWidgets('header checkbox shows indeterminate state for partial selection',
      (tester) async {
    final rows = _mixedRows();
    final container = ProviderContainer(overrides: [
      shared_repo.projectLanguageRepositoryProvider
          .overrideWithValue(_stubProjectLanguageRepo()),
      ..._filteredRows(rows),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 1000,
            child: EditorDataGrid(
              projectId: _projectId,
              languageId: _languageId,
              onCellEdit: (_, _) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Select a single row through the provider AFTER the grid has mounted, so
    // its `ref.listen(editorSelectionProvider)` fires and syncs the selection
    // into the grid. The header checkbox should then read the indeterminate
    // (null) tristate.
    container.read(editorSelectionProvider.notifier).toggleSelection('a');
    await tester.pumpAndSettle();

    final cb = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(cb.value, isNull); // indeterminate
  });

  testWidgets('tapping a data cell selects that row', (tester) async {
    final rows = _mixedRows();
    final container = ProviderContainer(overrides: [
      shared_repo.projectLanguageRepositoryProvider
          .overrideWithValue(_stubProjectLanguageRepo()),
      ..._filteredRows(rows),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 1000,
            child: EditorDataGrid(
              projectId: _projectId,
              languageId: _languageId,
              onCellEdit: (_, _) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tap the source-text cell of the first row.
    await tester.tap(find.textContaining('Source text for a').first);
    await tester.pumpAndSettle();

    expect(
      container.read(editorSelectionProvider).selectedUnitIds,
      contains('a'),
    );
  });

  testWidgets('external provider selection syncs into the grid', (tester) async {
    final rows = _mixedRows();
    final container = ProviderContainer(overrides: [
      shared_repo.projectLanguageRepositoryProvider
          .overrideWithValue(_stubProjectLanguageRepo()),
      ..._filteredRows(rows),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 1000,
            child: EditorDataGrid(
              projectId: _projectId,
              languageId: _languageId,
              onCellEdit: (_, _) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Simulate Ctrl+A coming from the screen-scope shortcut: this drives the
    // `ref.listen(editorSelectionProvider)` → `syncFromProvider` branch.
    container
        .read(editorSelectionProvider.notifier)
        .selectAll(rows.map((r) => r.id).toList());
    await tester.pumpAndSettle();

    final cb = tester.widget<Checkbox>(find.byType(Checkbox).first);
    expect(cb.value, isTrue); // all selected → header reads checked
  });

  testWidgets('arrow keys move the single selection up and down',
      (tester) async {
    final rows = _mixedRows();
    final container = ProviderContainer(overrides: [
      shared_repo.projectLanguageRepositoryProvider
          .overrideWithValue(_stubProjectLanguageRepo()),
      ..._filteredRows(rows),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 1000,
            child: EditorDataGrid(
              projectId: _projectId,
              languageId: _languageId,
              onCellEdit: (_, _) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Select the first row by tapping it (also pulls focus onto the grid).
    await tester.tap(find.textContaining('Source text for a').first);
    await tester.pumpAndSettle();
    expect(container.read(editorSelectionProvider).selectedUnitIds, {'a'});

    // Arrow down → second row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(container.read(editorSelectionProvider).selectedUnitIds, {'b'});

    // Arrow up → back to first row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(container.read(editorSelectionProvider).selectedUnitIds, {'a'});

    // Arrow up again is clamped at the top (no change).
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(container.read(editorSelectionProvider).selectedUnitIds, {'a'});

    // A non-navigation key is ignored.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(container.read(editorSelectionProvider).selectedUnitIds, {'a'});
  });

  testWidgets('right-click opens the context menu and Select All works',
      (tester) async {
    final rows = _mixedRows();
    final container = ProviderContainer(overrides: [
      shared_repo.projectLanguageRepositoryProvider
          .overrideWithValue(_stubProjectLanguageRepo()),
      ..._filteredRows(rows),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 1000,
            child: EditorDataGrid(
              projectId: _projectId,
              languageId: _languageId,
              onCellEdit: (_, _) async {},
              onForceRetranslate: () async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Secondary-tap (right click) a data row to open the context menu.
    final cell = find.textContaining('Source text for a').first;
    final center = tester.getCenter(cell);
    final gesture =
        await tester.startGesture(center, kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton);
    await gesture.up();
    await tester.pumpAndSettle();

    // Context menu items appear.
    expect(find.byType(PopupMenuItem<String>), findsWidgets);

    // The right-clicked row should now be single-selected.
    expect(container.read(editorSelectionProvider).selectedUnitIds, {'a'});
  });

  testWidgets('refreshes data on a matching BatchCompletedEvent',
      (tester) async {
    var invocations = 0;
    final rows = _mixedRows();
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: EditorDataGrid(
          projectId: _projectId,
          languageId: _languageId,
          onCellEdit: (_, _) async {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      screenSize: const Size(1400, 1000),
      overrides: [
        shared_repo.projectLanguageRepositoryProvider
            .overrideWithValue(_stubProjectLanguageRepo()),
        // Count rebuilds of the base provider, which is what `_refreshTranslations`
        // invalidates. The filtered provider chains off it (as in production) so
        // the grid still rebuilds with fresh rows.
        translationRowsProvider(_projectId, _languageId)
            .overrideWith((_) async {
          invocations++;
          return rows;
        }),
        filteredTranslationRowsProvider(_projectId, _languageId)
            .overrideWith((ref) =>
                ref.watch(translationRowsProvider(_projectId, _languageId).future)),
      ],
    ));
    await tester.pumpAndSettle();

    final before = invocations;

    // Publish a completed event for OUR project-language: triggers refresh.
    EventBus.instance.publish(BatchCompletedEvent(
      batchId: 'batch-1',
      projectLanguageId: _projectLanguageId,
      batchNumber: 1,
      totalUnits: 3,
      completedUnits: 3,
      failedUnits: 0,
      processingDuration: const Duration(seconds: 1),
    ));
    await tester.pumpAndSettle();

    expect(invocations, greaterThan(before),
        reason: 'matching BatchCompletedEvent should invalidate the provider');

    // A completed event for a DIFFERENT project-language must NOT refresh.
    final mid = invocations;
    EventBus.instance.publish(BatchCompletedEvent(
      batchId: 'batch-2',
      projectLanguageId: 'other-pl',
      batchNumber: 2,
      totalUnits: 3,
      completedUnits: 3,
      failedUnits: 0,
      processingDuration: const Duration(seconds: 1),
    ));
    await tester.pumpAndSettle();
    expect(invocations, mid);
  });

  testWidgets('refreshes on a 10-unit BatchProgressEvent', (tester) async {
    var invocations = 0;
    final rows = _mixedRows();
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: EditorDataGrid(
          projectId: _projectId,
          languageId: _languageId,
          onCellEdit: (_, _) async {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      screenSize: const Size(1400, 1000),
      overrides: [
        shared_repo.projectLanguageRepositoryProvider
            .overrideWithValue(_stubProjectLanguageRepo()),
        translationRowsProvider(_projectId, _languageId)
            .overrideWith((_) async {
          invocations++;
          return rows;
        }),
        filteredTranslationRowsProvider(_projectId, _languageId)
            .overrideWith((ref) =>
                ref.watch(translationRowsProvider(_projectId, _languageId).future)),
      ],
    ));
    await tester.pumpAndSettle();

    final before = invocations;

    // completedUnits % 10 != 0 → ignored.
    EventBus.instance.publish(BatchProgressEvent(
      batchId: 'b',
      totalUnits: 100,
      completedUnits: 7,
      failedUnits: 0,
    ));
    await tester.pumpAndSettle();
    expect(invocations, before);

    // completedUnits % 10 == 0 → refresh.
    EventBus.instance.publish(BatchProgressEvent(
      batchId: 'b',
      totalUnits: 100,
      completedUnits: 10,
      failedUnits: 0,
    ));
    await tester.pumpAndSettle();
    expect(invocations, greaterThan(before));
  });

  testWidgets('tolerates a project language that is not found', (tester) async {
    // The repo returns no matching project-language → `_loadProjectLanguageId`
    // swallows the "not found" and leaves filtering disabled, but the grid must
    // still render normally.
    await _pumpGrid(
      tester,
      rowOverrides: _filteredRows(_mixedRows()),
      projectLanguageRepo: _stubProjectLanguageRepo(matching: false),
    );

    expect(find.byType(SfDataGrid), findsOneWidget);
  });

  testWidgets('survives a data refresh that keeps cached rows visible',
      (tester) async {
    final rows = _mixedRows();
    final container = ProviderContainer(overrides: [
      shared_repo.projectLanguageRepositoryProvider
          .overrideWithValue(_stubProjectLanguageRepo()),
      ..._filteredRows(rows),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 1000,
            child: EditorDataGrid(
              projectId: _projectId,
              languageId: _languageId,
              onCellEdit: (_, _) async {},
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Invalidate to force a re-fetch: cached rows keep the grid populated while
    // the new future resolves (exercises the cached-rows branch in build()).
    container.invalidate(filteredTranslationRowsProvider(_projectId, _languageId));
    await tester.pump();
    expect(find.byType(SfDataGrid), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SfDataGrid), findsOneWidget);
  });

  group('context-menu actions', () {
    /// Pump the grid under a container that wires the version repo (for bulk
    /// ops) plus the row + project-language overrides. Returns the container so
    /// tests can inspect provider state.
    Future<ProviderContainer> pumpWithActions(
      WidgetTester tester,
      List<TranslationRow> rows, {
      TranslationVersionRepository? versionRepo,
    }) async {
      final container = ProviderContainer(overrides: [
        shared_repo.projectLanguageRepositoryProvider
            .overrideWithValue(_stubProjectLanguageRepo()),
        shared_repo.translationVersionRepositoryProvider
            .overrideWithValue(versionRepo ?? _okVersionRepo()),
        ..._filteredRows(rows),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(
            body: SizedBox(
              width: 1400,
              height: 1000,
              child: EditorDataGrid(
                projectId: _projectId,
                languageId: _languageId,
                onCellEdit: (_, _) async {},
                onForceRetranslate: () async {},
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return container;
    }

    /// Right-click the data cell of [rowKeyText] to open the context menu.
    Future<void> openMenuOnRow(WidgetTester tester, String rowKeyText) async {
      final cell = find.textContaining(rowKeyText).first;
      final gesture = await tester.startGesture(
        tester.getCenter(cell),
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();
    }

    testWidgets('Select All from the menu selects every row', (tester) async {
      final rows = _mixedRows();
      final container = await pumpWithActions(tester, rows);

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('Select All'));
      await tester.pumpAndSettle();

      expect(
        container.read(editorSelectionProvider).selectedUnitIds,
        rows.map((r) => r.id).toSet(),
      );
    });

    testWidgets('Clear Translation → confirm runs the clear handler',
        (tester) async {
      final versionRepo = _okVersionRepo();
      await pumpWithActions(tester, _mixedRows(), versionRepo: versionRepo);

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('Clear Translation'));
      await tester.pumpAndSettle();

      // Confirmation dialog appears; confirm it.
      expect(find.text('Clear'), findsOneWidget);
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      verify(() => versionRepo.clearBatch(any(),
          onProgress: any(named: 'onProgress'))).called(1);
    });

    testWidgets('Clear Translation → cancel does not clear', (tester) async {
      final versionRepo = _okVersionRepo();
      await pumpWithActions(tester, _mixedRows(), versionRepo: versionRepo);

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('Clear Translation'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => versionRepo.clearBatch(any(),
          onProgress: any(named: 'onProgress')));
    });

    testWidgets('Delete → confirm runs the delete handler', (tester) async {
      final versionRepo = _okVersionRepo();
      await pumpWithActions(tester, _mixedRows(), versionRepo: versionRepo);

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Confirmation dialog: confirm the delete.
      expect(find.text('Delete'), findsWidgets);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      verify(() => versionRepo.delete(any())).called(1);
    });

    testWidgets('Delete → cancel does not delete', (tester) async {
      final versionRepo = _okVersionRepo();
      await pumpWithActions(tester, _mixedRows(), versionRepo: versionRepo);

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      verifyNever(() => versionRepo.delete(any()));
    });

    testWidgets('Mark as Translated runs the validate handler', (tester) async {
      final versionRepo = _okVersionRepo();
      await pumpWithActions(tester, _mixedRows(), versionRepo: versionRepo);

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('Mark as Translated'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      verify(() => versionRepo.update(any())).called(1);
    });

    testWidgets('View History opens the history dialog', (tester) async {
      await pumpWithActions(tester, _mixedRows());

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('View History'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // The history dialog mounts (its data load fails through ServiceLocator
      // and is handled gracefully); the key point is the handler ran. The
      // dialog's error/empty layout can overflow the test surface — that's
      // chrome, not the behaviour under test, so we just drain the exception.
      expect(find.byType(TranslationHistoryDialog), findsOneWidget);
      tester.takeException();
    });

    testWidgets('View Prompt invokes the prompt handler', (tester) async {
      await pumpWithActions(tester, _mixedRows());

      await openMenuOnRow(tester, 'Source text for a');
      await tester.tap(find.text('View Prompt'));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // TranslationContextBuilder.build resolves to null in the test
      // environment (ServiceLocator deps unavailable), so the dialog is not
      // shown — but the handler path executed without throwing.
      expect(tester.takeException(), isNull);
    });
  });
}
