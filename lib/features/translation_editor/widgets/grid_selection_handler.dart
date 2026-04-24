import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';
import 'editor_data_source.dart';

/// Handler for grid selection operations
///
/// Manages single, multi, and range selection in the translation editor.
///
/// ## Anchor semantics
///
/// The shift-click anchor is stored as a **unit id** (`_anchorUnitId`) rather
/// than a positional index. Indices are resolved lazily against the current
/// `dataSource.translationRows` at click time. That way, filters, sort-order
/// changes, and live data refreshes (batch translation events) don't leave
/// the anchor pointing into random rows — a previous index-based anchor
/// would either crash (out-of-bounds subscript) or silently range-select the
/// wrong block of rows.
class GridSelectionHandler {
  final EditorDataSource dataSource;
  final DataGridController controller;
  final WidgetRef ref;
  final Function(Set<String>, int?) onSelectionChanged;

  /// Modifier-state readers. Injectable so tests can drive them without
  /// simulating raw key events on the global `HardwareKeyboard` singleton.
  /// Production defaults read the live keyboard state at click time.
  final bool Function() _isShiftPressed;
  final bool Function() _isCtrlPressed;

  Set<String> _selectedRowIds = {};
  String? _anchorUnitId;

  GridSelectionHandler({
    required this.dataSource,
    required this.controller,
    required this.ref,
    required this.onSelectionChanged,
    bool Function()? isShiftPressed,
    bool Function()? isCtrlPressed,
  })  : _isShiftPressed =
            isShiftPressed ?? (() => HardwareKeyboard.instance.isShiftPressed),
        _isCtrlPressed =
            isCtrlPressed ?? (() => HardwareKeyboard.instance.isControlPressed);

  Set<String> get selectedRowIds => _selectedRowIds;

  /// Current resolved position of the shift-click anchor in the visible
  /// dataset, or `null` if the anchor is unset or no longer visible.
  /// Exposed for arrow-key navigation in `EditorDataGrid`.
  int? get lastClickedIndex {
    final anchor = _anchorUnitId;
    if (anchor == null) return null;
    final idx = dataSource.translationRows.indexWhere((r) => r.id == anchor);
    return idx >= 0 ? idx : null;
  }

  bool isRowSelected(String unitId) => _selectedRowIds.contains(unitId);

  /// Select a single row (used for context menu)
  void selectSingleRow(String unitId, int rowIndex) {
    _handleNormalClick(unitId, rowIndex);
  }

  /// Handle cell tap with support for Ctrl and Shift modifiers
  void handleCellTap(DataGridCellTapDetails details) {
    if (details.rowColumnIndex.rowIndex == 0) return; // Header row

    // The CheckboxCellRenderer owns the tap gesture on the checkbox column,
    // so the grid's onCellTap must not also promote the row to a single
    // selection — that would clobber the multi-select the checkbox just
    // applied.
    if (details.column.columnName == 'checkbox') return;

    final rowIndex = details.rowColumnIndex.rowIndex - 1;
    if (rowIndex < 0 || rowIndex >= dataSource.translationRows.length) return;

    final unitId = dataSource.translationRows[rowIndex].id;
    handleRowTap(unitId, rowIndex);
  }

  /// Select a row by unit id, honouring Ctrl/Shift modifiers. Used when the
  /// row identity is known up front (e.g. a cell renderer that intercepted
  /// the primary click because `SelectableText` swallowed the tap before it
  /// reached Syncfusion's `onCellTap`).
  void handleRowTap(String unitId, int rowIndex) {
    if (_isCtrlPressed()) {
      _handleCtrlClick(unitId, rowIndex);
    } else if (_isShiftPressed()) {
      _handleShiftClick(unitId, rowIndex);
    } else {
      _handleNormalClick(unitId, rowIndex);
    }
  }

  /// Handle Ctrl+Click for multi-selection
  void _handleCtrlClick(String unitId, int rowIndex) {
    if (_selectedRowIds.contains(unitId)) {
      _selectedRowIds.remove(unitId);
    } else {
      _selectedRowIds.add(unitId);
    }
    _anchorUnitId = unitId;
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.toggleSelection(unitId);

    dataSource.refreshDisplay();

    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Handle Shift+Click for range selection.
  ///
  /// The anchor is resolved by id into the CURRENT `translationRows`, so the
  /// range survives filters, sorts, and data-set reorders between clicks.
  /// Falls back to a normal single-row click when no anchor can be
  /// resolved, so we never crash and never silently no-op.
  void _handleShiftClick(String unitId, int rowIndex) {
    final rows = dataSource.translationRows;
    if (rowIndex < 0 || rowIndex >= rows.length) return;

    final anchorIndex = _resolveAnchorIndex();
    if (anchorIndex == null) {
      _handleNormalClick(unitId, rowIndex);
      return;
    }

    final start = anchorIndex < rowIndex ? anchorIndex : rowIndex;
    final end = anchorIndex < rowIndex ? rowIndex : anchorIndex;

    final rangeIds = <String>{
      for (int i = start; i <= end; i++) rows[i].id,
    };

    _selectedRowIds = rangeIds;
    _updateDataGridSelection();

    // Intentionally do NOT update `_anchorUnitId`: the standard spreadsheet
    // contract is that repeated shift-clicks all re-range from the same
    // anchor, so the user can grow or shrink the selection by re-clicking.

    final notifier = ref.read(editorSelectionProvider.notifier);
    // Push the rangeIds directly instead of recomputing in the notifier:
    // `allUnitIds` reflects the current filter, and we've already computed
    // the correct set using current positions — keeps local + provider in
    // lockstep even in edge cases.
    notifier.replaceSelection(rangeIds);

    dataSource.refreshDisplay();

    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Handle normal click for single selection
  void _handleNormalClick(String unitId, int rowIndex) {
    // Idempotent path: if this row is already the sole selection, skip the
    // provider churn and `notifyListeners()`. On a dynamic-height
    // SfDataGrid, a redundant refresh causes Syncfusion to re-query row
    // heights and can visibly shift the scroll offset — reported as the
    // grid "jumping up" after clicking a tall row. We still update the
    // shift-click anchor so range-select from here behaves as expected.
    if (_selectedRowIds.length == 1 && _selectedRowIds.first == unitId) {
      _anchorUnitId = unitId;
      return;
    }

    _selectedRowIds = {unitId};
    _anchorUnitId = unitId;
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.replaceSelection({unitId});

    dataSource.refreshDisplay();

    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Handle checkbox tap.
  ///
  /// A checkbox tap is conceptually a Ctrl+click — it toggles a single row's
  /// membership in the selection without disturbing the rest. Historically
  /// this path did not touch the shift-click anchor, which meant a user who
  /// ticked a checkbox and then shift-clicked another row would see the
  /// range-select silently collapse to a single-row select (anchor was
  /// null). Treating the ticked row as the new anchor fixes that.
  void handleCheckboxTap(String unitId) {
    if (_selectedRowIds.contains(unitId)) {
      _selectedRowIds.remove(unitId);
    } else {
      _selectedRowIds.add(unitId);
    }
    _anchorUnitId = unitId;
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.toggleSelection(unitId);

    dataSource.refreshDisplay();

    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Select all rows
  void selectAll() {
    final allIds = dataSource.allUnitIds;
    _selectedRowIds = allIds.toSet();
    _anchorUnitId = allIds.isNotEmpty ? allIds.first : null;
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.selectAll(allIds);

    dataSource.refreshDisplay();

    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Mirror an external [editorSelectionProvider] mutation (e.g. a Ctrl+A
  /// fired from the screen-scope Shortcuts map) into the grid's local state.
  ///
  /// Unlike [selectAll]/[clearSelection]/etc., this path must NOT write back
  /// to the provider — it's reacting to a change that already happened there,
  /// and any re-emission would loop through the `ref.listen` that calls it.
  void syncFromProvider(Set<String> providerIds) {
    // Fast-path: identical membership → nothing to do. We still refresh the
    // anchor below so an externally-driven selection primes shift-click.
    final alreadyInSync = providerIds.length == _selectedRowIds.length &&
        _selectedRowIds.containsAll(providerIds);

    if (!alreadyInSync) {
      _selectedRowIds = Set<String>.from(providerIds);
    }

    // Keep the anchor aligned with what's actually selected:
    //   - empty selection → no anchor
    //   - current anchor still selected → keep it (avoids surprising the user)
    //   - otherwise → adopt the first visible row in the new selection so
    //     that a follow-up shift-click has a sensible origin (Ctrl+A from
    //     nothing ends up anchored on row 0, narrowing shift-clicks feel
    //     natural).
    if (_selectedRowIds.isEmpty) {
      _anchorUnitId = null;
      controller.selectedRows = [];
    } else if (_anchorUnitId == null ||
        !_selectedRowIds.contains(_anchorUnitId)) {
      _anchorUnitId = _firstSelectedInVisibleOrder() ?? _anchorUnitId;
      _updateDataGridSelection();
    } else {
      _updateDataGridSelection();
    }

    dataSource.refreshDisplay();
    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Clear selection
  void clearSelection() {
    _selectedRowIds.clear();
    _anchorUnitId = null;
    controller.selectedRows = [];

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.clearSelection();

    dataSource.refreshDisplay();

    onSelectionChanged(_selectedRowIds, lastClickedIndex);
  }

  /// Resolve the shift-click anchor to an index in the current filtered
  /// rows. Falls back to any existing single-row selection — so a user who
  /// selects one row from outside the handler (sidebar action, ctrl+A then
  /// ctrl-deselect down to one, etc.) can still shift-click to extend.
  int? _resolveAnchorIndex() {
    final rows = dataSource.translationRows;

    final anchor = _anchorUnitId;
    if (anchor != null) {
      final idx = rows.indexWhere((r) => r.id == anchor);
      if (idx >= 0) return idx;
    }

    if (_selectedRowIds.length == 1) {
      final onlyId = _selectedRowIds.first;
      final idx = rows.indexWhere((r) => r.id == onlyId);
      if (idx >= 0) {
        _anchorUnitId = onlyId;
        return idx;
      }
    }

    return null;
  }

  /// First row id in visible order that is part of the current selection.
  String? _firstSelectedInVisibleOrder() {
    for (final row in dataSource.translationRows) {
      if (_selectedRowIds.contains(row.id)) return row.id;
    }
    return null;
  }

  /// Update DataGrid controller with current selection
  void _updateDataGridSelection() {
    final selectedRows = dataSource.rows
        .asMap()
        .entries
        .where((entry) {
          if (entry.key >= dataSource.translationRows.length) return false;
          return _selectedRowIds.contains(dataSource.translationRows[entry.key].id);
        })
        .map((entry) => entry.value)
        .toList();

    controller.selectedRows = selectedRows;
  }
}
