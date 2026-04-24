import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/widgets/editor_data_source.dart';
import 'package:twmt/features/translation_editor/widgets/grid_selection_handler.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';

import '../../../helpers/test_bootstrap.dart';

TranslationRow _row(String id) {
  final unit = TranslationUnit(
    id: id,
    projectId: 'p',
    key: 'k-$id',
    sourceText: 's-$id',
    sourceLocFile: 'f.loc',
    createdAt: 0,
    updatedAt: 0,
  );
  final version = TranslationVersion(
    id: '$id-v',
    unitId: id,
    projectLanguageId: 'pl',
    translatedText: 't-$id',
    status: TranslationVersionStatus.translated,
    translationSource: TranslationSource.llm,
    createdAt: 0,
    updatedAt: 0,
  );
  return TranslationRow(unit: unit, version: version);
}

/// Harness that pumps a minimal Riverpod scope, surfaces a live `WidgetRef`,
/// and wires a `GridSelectionHandler` whose modifier-state callbacks are
/// controlled by the test rather than by the global `HardwareKeyboard`.
class _Harness {
  _Harness._({
    required this.ref,
    required this.dataSource,
    required this.handler,
    required this.shiftHeld,
    required this.ctrlHeld,
  });

  final WidgetRef ref;
  final EditorDataSource dataSource;
  final GridSelectionHandler handler;
  final _Flag shiftHeld;
  final _Flag ctrlHeld;

  static Future<_Harness> pump(
    WidgetTester tester,
    List<TranslationRow> initialRows,
  ) async {
    late WidgetRef capturedRef;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                capturedRef = ref;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );

    final dataSource = EditorDataSource(
      onCellEdit: (_, _) {},
      onCheckboxTap: (_) {},
      isRowSelected: (_) => false,
    );
    dataSource.updateDataSource(initialRows);

    final shiftHeld = _Flag();
    final ctrlHeld = _Flag();
    final handler = GridSelectionHandler(
      dataSource: dataSource,
      controller: DataGridController(),
      ref: capturedRef,
      onSelectionChanged: (_, _) {},
      isShiftPressed: () => shiftHeld.value,
      isCtrlPressed: () => ctrlHeld.value,
    );

    // Wire the data source's checkbox callback through the handler the same
    // way `EditorDataGrid.initState` does in production.
    dataSource.onCheckboxTap = handler.handleCheckboxTap;
    dataSource.isRowSelected = handler.isRowSelected;

    return _Harness._(
      ref: capturedRef,
      dataSource: dataSource,
      handler: handler,
      shiftHeld: shiftHeld,
      ctrlHeld: ctrlHeld,
    );
  }

  /// Simulate a plain row click at the current index in `translationRows`.
  void clickRow(String unitId) {
    final idx = dataSource.translationRows.indexWhere((r) => r.id == unitId);
    expect(idx, isNot(-1), reason: 'row $unitId not in current dataset');
    handler.handleRowTap(unitId, idx);
  }

  /// Simulate a Shift-click at the current index in `translationRows`.
  void shiftClickRow(String unitId) {
    shiftHeld.value = true;
    try {
      clickRow(unitId);
    } finally {
      shiftHeld.value = false;
    }
  }

  /// Simulate a Ctrl-click at the current index in `translationRows`.
  void ctrlClickRow(String unitId) {
    ctrlHeld.value = true;
    try {
      clickRow(unitId);
    } finally {
      ctrlHeld.value = false;
    }
  }

  Set<String> get providerSelection =>
      ref.read(editorSelectionProvider).selectedUnitIds;
}

class _Flag {
  bool value = false;
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('checkbox column cell-tap is a no-op', (tester) async {
    final h = await _Harness.pump(tester, [_row('a'), _row('b')]);

    h.handler.handleCellTap(
      DataGridCellTapDetails(
        rowColumnIndex: RowColumnIndex(1, 0),
        column: GridColumn(columnName: 'checkbox', label: const SizedBox()),
        globalPosition: Offset.zero,
        localPosition: Offset.zero,
        kind: PointerDeviceKind.mouse,
      ),
    );

    // CheckboxCellRenderer owns the tap on the checkbox column; the grid's
    // onCellTap must not also single-select or it clobbers multi-select.
    expect(h.ref.read(editorSelectionProvider).selectedCount, 0);
  });

  group('shift-click anchor robustness', () {
    testWidgets('checkbox tap primes the shift anchor', (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      // User ticks the checkbox on row 'b'.
      h.handler.handleCheckboxTap('b');
      expect(h.providerSelection, {'b'});

      // Shift-click on row 'd' must extend the selection to a contiguous
      // range from the last anchor (the checked row) to the clicked row.
      h.shiftClickRow('d');
      expect(h.providerSelection, {'b', 'c', 'd'});
    });

    testWidgets('ctrl-click primes the shift anchor for the next shift-click',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      h.ctrlClickRow('b');
      h.ctrlClickRow('d');
      // Now shift-click 'e' — the last ctrl-click ('d') is the anchor.
      h.shiftClickRow('e');
      expect(h.providerSelection, {'d', 'e'});
    });

    testWidgets('first interaction being a shift-click single-selects the row',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d')],
      );

      h.shiftClickRow('c');
      // With no prior anchor, shift-click degrades to a normal single-row
      // select. It must NOT no-op and must NOT crash.
      expect(h.providerSelection, {'c'});
    });

    testWidgets('shift-click after Ctrl+A ranges from the top to the clicked row',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      // Simulate Ctrl+A: the screen-scope shortcut pushes the selection
      // straight into the provider, and the grid mirrors it via
      // `syncFromProvider` — bypassing the handler's click paths.
      final notifier = h.ref.read(editorSelectionProvider.notifier);
      notifier.selectAll(h.dataSource.allUnitIds);
      h.handler.syncFromProvider({'a', 'b', 'c', 'd', 'e'});

      // A follow-up shift-click on row 'c' should narrow the selection to
      // rows 'a'..'c' — the standard spreadsheet behaviour after Select-All.
      h.shiftClickRow('c');
      expect(h.providerSelection, {'a', 'b', 'c'});
    });

    testWidgets('shift-click survives a filter that reorders the dataset',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      // Anchor on 'd' (originally at index 3).
      h.clickRow('d');

      // User applies a filter that hides 'a' and 'c'. The anchor row 'd'
      // is now at index 1 in the new dataset.
      h.dataSource.updateDataSource([_row('b'), _row('d'), _row('e')]);

      // Shift-click 'e' (now at index 2) must select 'd' and 'e', not
      // "index 3 to index 2" (which is both out of bounds and backwards).
      h.shiftClickRow('e');
      expect(h.providerSelection, {'d', 'e'});
    });

    testWidgets('shift-click reaching backwards into filtered-in rows works',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      h.clickRow('d');
      // Remove 'c' via filter — anchor 'd' is still present.
      h.dataSource.updateDataSource([_row('a'), _row('b'), _row('d'), _row('e')]);

      // Shift-click 'a' must select rows between 'a' and 'd' inclusive in
      // the CURRENT dataset order: {a, b, d}.
      h.shiftClickRow('a');
      expect(h.providerSelection, {'a', 'b', 'd'});
    });

    testWidgets('shift-click falls back to single-select when the anchor row is filtered out',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      h.clickRow('c');
      // Filter removes 'c' — the anchor id is no longer resolvable.
      h.dataSource.updateDataSource([_row('a'), _row('b'), _row('d'), _row('e')]);

      // Shift-click on 'd': with no resolvable anchor, behave as a single
      // select and re-prime the anchor on the clicked row.
      h.shiftClickRow('d');
      expect(h.providerSelection, {'d'});

      // Subsequent shift-click on 'a' must now range from the new anchor 'd'.
      h.shiftClickRow('a');
      expect(h.providerSelection, {'a', 'b', 'd'});
    });

    testWidgets('shift-click does not throw when anchor index would be out of bounds',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      // Anchor at the last row.
      h.clickRow('e');
      // Shrink the dataset so the old index (4) is now out of bounds.
      h.dataSource.updateDataSource([_row('a'), _row('b')]);

      // Must not throw, must produce a sane selection (single-row fallback).
      expect(() => h.shiftClickRow('a'), returnsNormally);
      expect(h.providerSelection, {'a'});
    });

    testWidgets('shift-click after rows are reordered uses id-based anchor',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      h.clickRow('b'); // anchor = 'b'

      // Dataset order flips (e.g. sort direction changed).
      h.dataSource.updateDataSource([_row('e'), _row('d'), _row('c'), _row('b'), _row('a')]);

      // 'b' is now at index 3. Shift-click 'd' (now at index 1) must select
      // the rows from 'b' to 'd' in the CURRENT visual order: {d, c, b}.
      h.shiftClickRow('d');
      expect(h.providerSelection, {'b', 'c', 'd'});
    });

    testWidgets('repeated shift-clicks keep the same anchor', (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      h.clickRow('b'); // anchor = 'b'
      h.shiftClickRow('d');
      expect(h.providerSelection, {'b', 'c', 'd'});

      // Second shift-click should re-range from the same anchor 'b', not
      // from the previous shift-click target 'd'.
      h.shiftClickRow('e');
      expect(h.providerSelection, {'b', 'c', 'd', 'e'});

      h.shiftClickRow('a');
      expect(h.providerSelection, {'a', 'b'});
    });

    testWidgets('shift-click when only a non-anchor row is selected picks up the selection as anchor',
        (tester) async {
      final h = await _Harness.pump(
        tester,
        [_row('a'), _row('b'), _row('c'), _row('d'), _row('e')],
      );

      // Drive a selection purely through the provider (e.g. from the sidebar)
      // without going through the handler's click paths.
      final notifier = h.ref.read(editorSelectionProvider.notifier);
      notifier.toggleSelection('b');
      h.handler.syncFromProvider({'b'});

      // Shift-click 'd' — the anchor hasn't been set by the handler itself,
      // but a single row is selected. The handler should treat that lone
      // selection as the anchor rather than discarding it.
      h.shiftClickRow('d');
      expect(h.providerSelection, {'b', 'c', 'd'});
    });
  });
}
