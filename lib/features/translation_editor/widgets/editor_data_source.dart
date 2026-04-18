import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../providers/editor_providers.dart';
import 'cell_renderers/checkbox_cell_renderer.dart';
import 'cell_renderers/text_cell_renderer.dart';

/// DataSource for Syncfusion DataGrid
///
/// Handles data display and inline editing for translation rows
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

  // Memory management: Track edit controllers to dispose them properly
  TextEditingController? _activeEditController;

  EditorDataSource({
    required this.onCellEdit,
    required this.onCheckboxTap,
    required this.isRowSelected,
    this.onCellSecondaryTap,
  });

  /// Dispose resources to prevent memory leaks
  @override
  void dispose() {
    _activeEditController?.dispose();
    _activeEditController = null;
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

  @override
  Future<void> onCellSubmit(
    DataGridRow dataGridRow,
    RowColumnIndex rowColumnIndex,
    GridColumn column,
  ) async {
    final dynamic oldValue = dataGridRow
      .getCells()
      .firstWhere((cell) => cell.columnName == column.columnName)
      .value;

    final dynamic newValue = newCellValue;

    if (oldValue == newValue || newValue == null) {
      return;
    }

    // Find the row index
    final rowIndex = rows.indexOf(dataGridRow);
    if (rowIndex == -1) return;

    final row = _rows[rowIndex];

    // Only allow editing of translated text column
    if (column.columnName == 'translatedText') {
      onCellEdit(row.id, newValue.toString());
    }
  }

  dynamic newCellValue;

  /// Escape special characters for display (actual newlines → \n literal)
  static String _escapeForDisplay(String text) {
    return text
        .replaceAll('\r\n', '\\r\\n')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
  }

  /// Unescape special characters for storage (\n literal → actual newlines)
  static String _unescapeForStorage(String text) {
    return text
        .replaceAll('\\r\\n', '\r\n')
        .replaceAll('\\n', '\n')
        .replaceAll('\\r', '\r')
        .replaceAll('\\t', '\t');
  }

  @override
  Widget? buildEditWidget(
    DataGridRow dataGridRow,
    RowColumnIndex rowColumnIndex,
    GridColumn column,
    CellSubmit submitCell,
  ) {
    // Only allow editing of translated text column
    if (column.columnName != 'translatedText') {
      return null;
    }

    final String? rawText = dataGridRow
      .getCells()
      .firstWhere((cell) => cell.columnName == column.columnName)
      .value;

    // Show escaped text in editor (newlines displayed as \n)
    final escapedText = _escapeForDisplay(rawText ?? '');
    newCellValue = rawText;

    // Memory management: Dispose previous controller before creating new one
    _activeEditController?.dispose();
    _activeEditController = TextEditingController(text: escapedText);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      alignment: Alignment.centerLeft,
      child: TextField(
        autofocus: true,
        controller: _activeEditController,
        style: const TextStyle(fontSize: 13),
        maxLines: null,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (value) {
          // Convert escaped sequences back to actual characters for storage
          newCellValue = _unescapeForStorage(value);
        },
        onSubmitted: (value) {
          // Convert escaped sequences back to actual characters for storage
          newCellValue = _unescapeForStorage(value);
          submitCell();
        },
      ),
    );
  }
}
