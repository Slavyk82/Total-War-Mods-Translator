// Line-coverage extension for [TmBrowserDataGrid].
//
// The sibling `tm_browser_datagrid_test.dart` locks the behavioural
// invariants (data-source reuse, delete refresh, sort guard). This file
// drives the remaining ~25% of branches that those tests never reach:
//   - the error and empty states,
//   - the row checkbox cell + the select-all header (toggle / clear),
//   - single-tap selection + double-tap edit cell callbacks,
//   - the edit-dialog flow (`_handleEditEntry` + optimistic `patchEntry`),
//   - the delete-failure toast branch,
//   - the `_LastUsedCell` tooltip variant.
//
// House rules (proven): pump under a themed `MaterialApp`
// (`AppTheme.atelierDarkTheme`) with the grid inside a `Scaffold` (the
// checkbox cells need a Material ancestor); surface 1400x1000 @ dPR 1.0 with
// addTearDown resets; override the clock + TM service providers with crafted
// data.
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderContainer, UncontrolledProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/features/translation_memory/providers/tm_providers.dart';
import 'package:twmt/features/translation_memory/providers/tm_selection_notifier.dart';
import 'package:twmt/features/translation_memory/widgets/tm_browser_datagrid.dart';
import 'package:twmt/features/translation_memory/widgets/tm_edit_dialog.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

const int _baseEpoch = 1_700_000_000;

TranslationMemoryEntry _entry(String id, String src, String tgt) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: src,
      sourceHash: id,
      sourceLanguageId: 'lang_en',
      targetLanguageId: 'lang_fr',
      translatedText: tgt,
      usageCount: 1,
      createdAt: _baseEpoch,
      lastUsedAt: _baseEpoch,
      updatedAt: _baseEpoch,
    );

/// Configurable fake TM service.
///
/// - [getEntries]/[searchEntries] either return the live store or, when
///   [failGet] is set, an [Err] so `tmEntriesProvider` throws and the widget
///   takes the error branch.
/// - [updateTargetText] applies the edit so the optimistic-patch save path
///   shows the new translation.
/// - [deleteEntry] honours [failDelete] so the delete-failure toast renders.
class _FakeTmService implements ITranslationMemoryService {
  _FakeTmService(
    List<TranslationMemoryEntry> entries, {
    this.failGet = false,
    this.failDelete = false,
  }) : _entries = List.of(entries);

  final List<TranslationMemoryEntry> _entries;
  final bool failGet;
  final bool failDelete;

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async {
    if (failGet) return Err(const TmServiceException('boom'));
    return Ok(List.of(_entries));
  }

  @override
  Future<Result<int, TmServiceException>> countEntries({
    String? targetLanguageCode,
  }) async =>
      Ok(_entries.length);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = 50,
  }) async {
    if (failGet) return Err(const TmServiceException('boom'));
    return Ok(List.of(_entries));
  }

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) async =>
      Ok(TmStatistics(
        totalEntries: _entries.length,
        entriesByLanguagePair: const {'en → fr': 0},
        totalReuseCount: 0,
        tokensSaved: 0,
        averageFuzzyScore: 0,
        reuseRate: 0,
      ));

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>> updateTargetText({
    required String entryId,
    required String newTargetText,
  }) async {
    final i = _entries.indexWhere((e) => e.id == entryId);
    if (i >= 0) {
      _entries[i] = _entries[i].copyWith(translatedText: newTargetText);
    }
    return Ok(_entries[i]);
  }

  @override
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) async {
    if (failDelete) return Err(const TmServiceException('delete failed'));
    _entries.removeWhere((e) => e.id == entryId);
    return const Ok(null);
  }

  // ---------------- Unused by the widget under test ----------------
  @override
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  }) async =>
      Err(const TmAddException('not implemented'));

  @override
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  }) async =>
      const Ok(0);

  @override
  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
  }) async =>
      const Ok(null);

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    String? category,
  }) async =>
      const Ok(null);

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatchesIsolate({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = 0.85,
    int maxResults = 5,
    String? category,
  }) async =>
      const Ok([]);

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({
    required String entryId,
  }) async =>
          Err(const TmServiceException('not implemented'));

  @override
  Future<Result<int, TmServiceException>> incrementUsageCountBatch(
    Map<String, int> usageCounts,
  ) async =>
      const Ok(0);

  @override
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = 365,
  }) async =>
      const Ok(0);

  @override
  Future<Result<int, TmImportException>> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async =>
      const Ok(0);

  @override
  Future<Result<int, TmExportException>> exportToTmx({
    required String outputPath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
    int? minUsageCount,
    bool includeMetadata = true,
    bool includeStats = true,
  }) async =>
      const Ok(0);

  @override
  Future<void> clearCache() async {}

  @override
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = 10000,
  }) async =>
      const Ok(null);

  @override
  Future<Result<({int added, int existing}), TmServiceException>>
      rebuildFromTranslations({
    String? projectId,
    void Function(int processed, int total, int added)? onProgress,
  }) async =>
          const Ok((added: 0, existing: 0));

  @override
  Future<Result<int, TmServiceException>> migrateLegacyHashes({
    void Function(int processed, int total)? onProgress,
  }) async =>
      const Ok(0);
}

List<Override> _overrides(_FakeTmService service) => [
      clockProvider.overrideWithValue(
        () => DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
            .add(const Duration(days: 1)),
      ),
      translationMemoryServiceProvider.overrideWithValue(service),
    ];

/// Pump the grid in a themed [MaterialApp] + [Scaffold] driven by an
/// [UncontrolledProviderScope] so each test can read provider state directly.
Future<ProviderContainer> _pumpGrid(
  WidgetTester t,
  _FakeTmService service,
) async {
  await t.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => t.binding.setSurfaceSize(null));
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetDevicePixelRatio);

  final container = ProviderContainer(overrides: _overrides(service));
  addTearDown(container.dispose);

  await t.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(body: TmBrowserDataGrid()),
      ),
    ),
  );
  await t.pumpAndSettle();
  return container;
}

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  testWidgets('renders the empty state when there are no entries', (t) async {
    final container = await _pumpGrid(t, _FakeTmService(const []));

    // The grid itself must not be present; the empty placeholder is shown.
    expect(find.byType(SfDataGrid), findsNothing);
    expect(find.text('No translation memory entries'), findsOneWidget);
    expect(
      find.text(
          'Import a TMX file or start translating to build your memory'),
      findsOneWidget,
    );
    container.dispose();
  });

  testWidgets('renders the error state when the entries provider throws',
      (t) async {
    await _pumpGrid(t, _FakeTmService(const [], failGet: true));

    expect(find.byType(SfDataGrid), findsNothing);
    expect(find.text('Failed to load entries'), findsOneWidget);
    // The error string is surfaced underneath the headline.
    expect(
      find.textContaining('boom'),
      findsOneWidget,
    );
  });

  testWidgets(
      'tapping a row checkbox toggles the entry in the selection provider',
      (t) async {
    final container = await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
        _entry('tm2', 'World', 'Monde'),
      ]),
    );

    expect(container.read(tmSelectionProvider), isEmpty);

    // Checkboxes: index 0 = select-all header, 1.. = row checkboxes.
    final checkboxes = find.byType(Checkbox);
    expect(checkboxes, findsAtLeast(3));

    await t.tap(checkboxes.at(1));
    await t.pumpAndSettle();

    expect(container.read(tmSelectionProvider), contains('tm1'));

    // Toggle off again.
    await t.tap(find.byType(Checkbox).at(1));
    await t.pumpAndSettle();
    expect(container.read(tmSelectionProvider), isNot(contains('tm1')));
  });

  testWidgets(
      'select-all header checkbox selects every visible row, then clears',
      (t) async {
    final container = await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
        _entry('tm2', 'World', 'Monde'),
        _entry('tm3', 'Foo', 'Bar'),
      ]),
    );

    // The header hosts the only tristate Checkbox (row checkboxes are not
    // tristate). Syncfusion clips it to ~14px inside the 32px header row and
    // overlays its own header gesture surface, so a synthetic pointer tap is
    // unreliable. Invoke the Checkbox's `onChanged` directly — that runs the
    // exact `toggle()` closure the production header wires up.
    Checkbox headerCheckbox() => t.widget<Checkbox>(
        find.byWidgetPredicate((w) => w is Checkbox && w.tristate == true));

    // value == false -> selectAll branch.
    headerCheckbox().onChanged!(true);
    await t.pumpAndSettle();
    expect(container.read(tmSelectionProvider),
        containsAll(<String>['tm1', 'tm2', 'tm3']));

    // value == true now -> clear branch.
    headerCheckbox().onChanged!(false);
    await t.pumpAndSettle();
    expect(container.read(tmSelectionProvider), isEmpty);
  });

  testWidgets(
      'header checkbox shows the tristate (null) value with a partial '
      'selection then selecting completes it',
      (t) async {
    final container = await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
        _entry('tm2', 'World', 'Monde'),
      ]),
    );

    // Seed a partial selection so the header renders the indeterminate state.
    container.read(tmSelectionProvider.notifier).toggle('tm1');
    await t.pumpAndSettle();

    Checkbox headerCheckbox() => t.widget<Checkbox>(find.byWidgetPredicate(
        (w) => w is Checkbox && w.tristate == true));
    expect(headerCheckbox().value, isNull,
        reason: 'partial selection -> tristate header');

    // From the partial state (value == null != true) the toggle selects all.
    // Invoke `onChanged` directly — the clipped header checkbox is not a
    // reliable synthetic-tap target.
    headerCheckbox().onChanged!(true);
    await t.pumpAndSettle();
    expect(container.read(tmSelectionProvider),
        containsAll(<String>['tm1', 'tm2']));
  });

  // NOTE on `onCellTap`: Syncfusion does not deliver a single `onCellTap`
  // through synthetic pointer taps when `SelectionMode.single` is active — the
  // selection recognizer wins the gesture arena in the test harness, so a
  // plain tap never reaches the widget's `onCellTap` handler. (The editor grid
  // that DOES tap-select in tests runs with `SelectionMode.none`.) The handler
  // is instead exercised by invoking it directly with crafted details further
  // below; the double-tap path is reachable via a real gesture and is covered
  // in the dialog test that follows.

  testWidgets(
      'double-tapping a body cell opens the edit dialog; saving patches the '
      'grid in place (optimistic update)',
      (t) async {
    await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
        _entry('tm2', 'World', 'Monde'),
      ]),
    );

    expect(find.text('Bonjour'), findsOneWidget);

    // Double tap the source cell of the first row.
    final cell = find.text('Hello');
    final center = t.getCenter(cell);
    final gesture = await t.startGesture(center);
    await gesture.up();
    await t.pump(const Duration(milliseconds: 50));
    await gesture.down(center);
    await gesture.up();
    await t.pumpAndSettle();

    // The edit dialog must be open.
    expect(find.byType(TmEditDialog), findsOneWidget);

    // Type a new translation and save.
    await t.enterText(find.byType(TextField).first, 'Salut');
    await t.pumpAndSettle();

    await t.tap(find.text('Save'));
    // Bounded pumps: the success toast schedules a dismiss timer.
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    // Dialog closed and the grid reflects the optimistic patch.
    expect(find.byType(TmEditDialog), findsNothing);
    expect(find.text('Salut'), findsOneWidget);
    expect(find.text('Bonjour'), findsNothing);

    // Drain the toast timer.
    await t.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'edit-dialog Cancel does not patch the grid (newTargetText == null '
      'short-circuit)', (t) async {
    await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
      ]),
    );

    // Open via the edit icon button in the actions cell.
    await t.tap(find.byTooltip('Edit entry').first);
    await t.pumpAndSettle();
    expect(find.byType(TmEditDialog), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();

    expect(find.byType(TmEditDialog), findsNothing);
    // Unchanged value remains.
    expect(find.text('Bonjour'), findsOneWidget);
  });

  testWidgets('delete failure surfaces the error toast (delete error branch)',
      (t) async {
    await _pumpGrid(
      t,
      _FakeTmService(
        [_entry('tm1', 'Hello', 'Bonjour')],
        failDelete: true,
      ),
    );

    await t.tap(find.byTooltip('Delete entry').first);
    await t.pumpAndSettle();

    // Confirm the destructive action.
    await t.tap(find.text('Delete'));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }

    // The row is still present (delete failed) and the error toast shows.
    expect(find.text('Hello'), findsOneWidget);
    expect(find.text('Failed to delete TM entry'), findsOneWidget);

    await t.pump(const Duration(seconds: 5));
  });

  testWidgets(
      'the lastUsed cell renders a relative label inside a tooltip wrapper',
      (t) async {
    await _pumpGrid(
      t,
      _FakeTmService([_entry('tm1', 'Hello', 'Bonjour')]),
    );

    // clockProvider is _baseEpoch + 1 day, lastUsedAt == _baseEpoch -> "1 day".
    expect(find.text('1 day'), findsOneWidget);
    // The absolute timestamp is non-null so the cell wraps the label in a
    // Tooltip.
    expect(find.byType(Tooltip), findsWidgets);
  });

  testWidgets('selection retain drops ids no longer in the visible list',
      (t) async {
    final service = _FakeTmService([
      _entry('tm1', 'Hello', 'Bonjour'),
      _entry('tm2', 'World', 'Monde'),
    ]);
    final container = await _pumpGrid(t, service);

    // Select both, then delete one through the provider. The post-frame
    // retain must prune the stale id from the selection set.
    container.read(tmSelectionProvider.notifier).selectAll({'tm1', 'tm2'});
    await t.pumpAndSettle();
    expect(container.read(tmSelectionProvider), hasLength(2));

    await container.read(tmDeleteStateProvider.notifier).deleteEntry('tm1');
    await t.pumpAndSettle();

    expect(container.read(tmSelectionProvider), <String>{'tm2'});
  });

  // The `onCellTap` handler cannot be reached through a synthetic pointer tap
  // (see the NOTE above), so invoke it directly with crafted
  // [DataGridCellTapDetails] to cover the header-row guard, the
  // actions/checkbox column short-circuits and the `rowAt`-driven selection.
  testWidgets('onCellTap: header row + actions/checkbox columns are ignored, '
      'a body cell selects the entry', (t) async {
    final container = await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
        _entry('tm2', 'World', 'Monde'),
      ]),
    );

    final grid = t.widget<SfDataGrid>(find.byType(SfDataGrid));
    final columns = {for (final c in grid.columns) c.columnName: c};

    DataGridCellTapDetails details(int rowIndex, String column) =>
        DataGridCellTapDetails(
          rowColumnIndex: RowColumnIndex(rowIndex, 0),
          column: columns[column]!,
          globalPosition: Offset.zero,
          localPosition: Offset.zero,
          kind: PointerDeviceKind.mouse,
        );

    // Keep `selectedTmEntryProvider` (autoDispose) alive for the duration of
    // the assertions so a one-shot `read` after the handler runs does not see
    // a freshly-rebuilt (null) state.
    final sub = container.listen(selectedTmEntryProvider, (_, _) {});
    addTearDown(sub.close);

    // Ignored branches: header row (rowIndex 0), actions column, checkbox
    // column. None of these mutate the selection.
    grid.onCellTap!(details(0, 'source'));
    grid.onCellTap!(details(1, 'actions'));
    grid.onCellTap!(details(1, 'checkbox'));
    expect(container.read(selectedTmEntryProvider), isNull);

    // Body cell at grid rowIndex 1 maps to data row 0 (tm1).
    grid.onCellTap!(details(1, 'source'));
    expect(container.read(selectedTmEntryProvider)?.id, 'tm1');

    // Out-of-range row -> `rowAt` returns null -> selection unchanged.
    grid.onCellTap!(details(99, 'source'));
    expect(container.read(selectedTmEntryProvider)?.id, 'tm1');
  });

  testWidgets(
      'onCellDoubleTap on a body cell opens the edit dialog; header / action '
      'columns are ignored', (t) async {
    await _pumpGrid(
      t,
      _FakeTmService([_entry('tm1', 'Hello', 'Bonjour')]),
    );

    final grid = t.widget<SfDataGrid>(find.byType(SfDataGrid));
    final columns = {for (final c in grid.columns) c.columnName: c};

    DataGridCellDoubleTapDetails details(int rowIndex, String column) =>
        DataGridCellDoubleTapDetails(
          rowColumnIndex: RowColumnIndex(rowIndex, 0),
          column: columns[column]!,
        );

    // Ignored branches: header row, actions and checkbox columns.
    grid.onCellDoubleTap!(details(0, 'source'));
    grid.onCellDoubleTap!(details(1, 'actions'));
    grid.onCellDoubleTap!(details(1, 'checkbox'));
    // Out-of-range body cell -> rowAt null -> no dialog.
    grid.onCellDoubleTap!(details(99, 'source'));
    await t.pumpAndSettle();
    expect(find.byType(TmEditDialog), findsNothing);

    // Valid body cell opens the edit dialog.
    grid.onCellDoubleTap!(details(1, 'source'));
    await t.pumpAndSettle();
    expect(find.byType(TmEditDialog), findsOneWidget);
  });

  testWidgets('the data source compare() is a no-op (sorting is server-side)',
      (t) async {
    await _pumpGrid(
      t,
      _FakeTmService([
        _entry('tm1', 'Hello', 'Bonjour'),
        _entry('tm2', 'World', 'Monde'),
      ]),
    );

    // The live grid source is the production `_TmDataSource`; its `compare`
    // override always returns 0 because real ordering happens server-side.
    // `compare` is `@protected` on `DataGridSource`; calling it from the test
    // is deliberate to cover the override.
    final source = t.widget<SfDataGrid>(find.byType(SfDataGrid)).source;
    // ignore: invalid_use_of_protected_member
    final result = source.compare(
      source.rows.first,
      source.rows.last,
      const SortColumnDetails(
        name: 'source',
        sortDirection: DataGridSortDirection.ascending,
      ),
    );
    expect(result, 0);
  });
}
