import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';
import 'cell_renderers/checkbox_cell_renderer.dart';
import 'cell_renderers/text_cell_renderer.dart';

/// DataSource for Syncfusion DataGrid
///
/// Read-only surface: editing flows through the inspector panel via
/// `handleCellEdit`, not inline grid editing. The `onCellEdit` callback is
/// kept so the inspector can write through the data source.
class EditorDataSource extends DataGridSource {
  List<TranslationRow> _rows = [];
  final Function(String unitId, String newText) onCellEdit;
  Function(String unitId) onCheckboxTap;
  bool Function(String unitId) isRowSelected;
  /// Callback for secondary tap (right-click) on a cell to show context menu
  Function(TranslationRow row, Offset globalPosition)? onCellSecondaryTap;

  Color? _selectedRowColor;

  /// Token-aware background colour for selected rows. Plumbed in from the
  /// datagrid when it builds, so the data source stays theme-agnostic.
  // ignore: use_setters_to_change_properties
  void setSelectedRowColor(Color color) {
    _selectedRowColor = color;
  }

  // Performance: Cache for DataGridRow objects to avoid rebuilding unchanged rows
  final Map<int, DataGridRow> _rowCache = {};

  // Performance: id → row lookup table, kept in sync with `_rows` so
  // `buildRow` avoids O(N) firstWhere scans on every visible cell.
  final Map<String, TranslationRow> _rowsById = <String, TranslationRow>{};

  EditorDataSource({
    required this.onCellEdit,
    required this.onCheckboxTap,
    required this.isRowSelected,
    this.onCellSecondaryTap,
  });

  /// Dispose resources to prevent memory leaks
  @override
  void dispose() {
    _rowCache.clear();
    _rowsById.clear();
    super.dispose();
  }

  /// Update the data rows
  /// Performance: Only notifies listeners if data actually changed
  void updateDataSource(List<TranslationRow> rows) {
    if (_rows == rows) return; // Early exit if data hasn't changed
    _rows = rows;
    _rowCache.clear(); // Clear cache when data changes
    _rowsById
      ..clear()
      ..addEntries(rows.map((r) => MapEntry(r.id, r)));
    notifyListeners();
  }

  /// Get all translation row data
  List<TranslationRow> get translationRows => _rows;

  /// Get all unit IDs
  List<String> get allUnitIds => _rows.map((row) => row.id).toList();

  /// O(1) lookup of the full `TranslationRow` for a given unit id. Falls back
  /// to the first row if `id` is unknown (the old `firstWhere` behaviour).
  TranslationRow rowById(String id) =>
      _rowsById[id] ?? _rows.first;

  /// Notify listeners to refresh display (e.g., after selection change)
  void refreshDisplay() {
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows.asMap().entries.map((entry) {
    final index = entry.key;
    final row = entry.value;

    return _rowCache.putIfAbsent(index, () {
      return DataGridRow(
        cells: [
          DataGridCell<String>(columnName: 'checkbox', value: row.id),
          DataGridCell<String>(columnName: 'key', value: row.key),
          DataGridCell<String>(columnName: 'sourceText', value: row.sourceText),
          DataGridCell<String?>(
            columnName: 'translatedText',
            value: row.translatedText,
          ),
        ],
      );
    });
  }).toList();

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final unitId = cells[0].value as String;
    final keyValue = cells[1].value as String;
    final sourceTextValue = cells[2].value as String;
    final translatedTextValue = cells[3].value as String?;

    final isSelected = isRowSelected(unitId);
    final translationRow = rowById(unitId);

    void handleSecondaryTap(Offset position) {
      onCellSecondaryTap?.call(translationRow, position);
    }

    return DataGridRowAdapter(
      color: isSelected ? _selectedRowColor : null,
      cells: [
        RepaintBoundary(
          child: CheckboxCellRenderer(
            isSelected: isSelected,
            onTap: () => onCheckboxTap(unitId),
          ),
        ),
        RepaintBoundary(
          child: TextCellRenderer(
            text: keyValue,
            isKey: true,
            onSecondaryTap: handleSecondaryTap,
          ),
        ),
        TextCellRenderer(
          text: sourceTextValue,
          onSecondaryTap: handleSecondaryTap,
        ),
        TextCellRenderer(
          text: translatedTextValue,
          onSecondaryTap: handleSecondaryTap,
        ),
      ],
    );
  }

}
