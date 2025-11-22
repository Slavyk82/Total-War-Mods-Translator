import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';
import 'editor_data_source.dart';

/// Handler for grid selection operations
///
/// Manages single, multi, and range selection in the translation editor
class GridSelectionHandler {
  final EditorDataSource dataSource;
  final DataGridController controller;
  final WidgetRef ref;
  final Function(Set<String>, int?) onSelectionChanged;

  Set<String> _selectedRowIds = {};
  int? _lastClickedIndex;

  GridSelectionHandler({
    required this.dataSource,
    required this.controller,
    required this.ref,
    required this.onSelectionChanged,
  });

  Set<String> get selectedRowIds => _selectedRowIds;
  int? get lastClickedIndex => _lastClickedIndex;

  bool isRowSelected(String unitId) => _selectedRowIds.contains(unitId);

  /// Select a single row (used for context menu)
  void selectSingleRow(String unitId, int rowIndex) {
    _handleNormalClick(unitId, rowIndex);
  }

  /// Handle cell tap with support for Ctrl and Shift modifiers
  void handleCellTap(DataGridCellTapDetails details) {
    if (details.rowColumnIndex.rowIndex == 0) return; // Header row

    final rowIndex = details.rowColumnIndex.rowIndex - 1;
    if (rowIndex < 0 || rowIndex >= dataSource.rows.length) return;

    final unitId = dataSource.translationRows[rowIndex].id;
    final isCtrlPressed = HardwareKeyboard.instance.isControlPressed;
    final isShiftPressed = HardwareKeyboard.instance.isShiftPressed;

    // DEBUG: Log selection mode
    debugPrint('Cell tapped: row=$rowIndex, ctrl=$isCtrlPressed, shift=$isShiftPressed');

    if (isCtrlPressed) {
      _handleCtrlClick(unitId, rowIndex);
    } else if (isShiftPressed) {
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
    _lastClickedIndex = rowIndex;
    _updateDataGridSelection();

    // DEBUG: Log multi-selection
    debugPrint('Ctrl+Click: ${_selectedRowIds.length} rows selected');

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.toggleSelection(unitId);

    onSelectionChanged(_selectedRowIds, _lastClickedIndex);
  }

  /// Handle Shift+Click for range selection
  void _handleShiftClick(String unitId, int rowIndex) {
    if (_lastClickedIndex == null) {
      _handleNormalClick(unitId, rowIndex);
      return;
    }

    final start = _lastClickedIndex! < rowIndex ? _lastClickedIndex! : rowIndex;
    final end = _lastClickedIndex! < rowIndex ? rowIndex : _lastClickedIndex!;

    _selectedRowIds.clear();
    for (int i = start; i <= end; i++) {
      if (i < dataSource.translationRows.length) {
        _selectedRowIds.add(dataSource.translationRows[i].id);
      }
    }

    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    final allIds = dataSource.allUnitIds;
    final startId = dataSource.translationRows[_lastClickedIndex!].id;
    notifier.selectRange(startId, unitId, allIds);

    onSelectionChanged(_selectedRowIds, _lastClickedIndex);
  }

  /// Handle normal click for single selection
  void _handleNormalClick(String unitId, int rowIndex) {
    _selectedRowIds = {unitId};
    _lastClickedIndex = rowIndex;
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.clearSelection();
    notifier.toggleSelection(unitId);

    onSelectionChanged(_selectedRowIds, _lastClickedIndex);
  }

  /// Handle checkbox tap
  void handleCheckboxTap(String unitId) {
    if (_selectedRowIds.contains(unitId)) {
      _selectedRowIds.remove(unitId);
    } else {
      _selectedRowIds.add(unitId);
    }
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.toggleSelection(unitId);

    // DEBUG: Log checkbox selection
    debugPrint('Checkbox clicked: ${_selectedRowIds.length} rows selected');

    onSelectionChanged(_selectedRowIds, _lastClickedIndex);
  }

  /// Select all rows
  void selectAll() {
    _selectedRowIds = dataSource.allUnitIds.toSet();
    if (dataSource.translationRows.isNotEmpty) {
      _lastClickedIndex = dataSource.translationRows.length - 1;
    }
    _updateDataGridSelection();

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.selectAll(dataSource.allUnitIds);

    onSelectionChanged(_selectedRowIds, _lastClickedIndex);
  }

  /// Clear selection
  void clearSelection() {
    _selectedRowIds.clear();
    _lastClickedIndex = null;
    controller.selectedRows = [];

    final notifier = ref.read(editorSelectionProvider.notifier);
    notifier.clearSelection();

    onSelectionChanged(_selectedRowIds, _lastClickedIndex);
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
