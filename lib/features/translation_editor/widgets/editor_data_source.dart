import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/models/domain/translation_version.dart';
import '../providers/editor_providers.dart';
import 'cell_renderers/checkbox_cell_renderer.dart';
import 'cell_renderers/status_cell_renderer.dart';
import 'cell_renderers/text_cell_renderer.dart';
import 'cell_renderers/confidence_cell_renderer.dart';

/// DataSource for Syncfusion DataGrid
///
/// Handles data display and inline editing for translation rows
class EditorDataSource extends DataGridSource {
  List<TranslationRow> _rows = [];
  final Function(String unitId, String newText) onCellEdit;
  final Function(String unitId) onCellTap;
  Function(String unitId) onCheckboxTap;
  bool Function(String unitId) isRowSelected;

  // Performance: Cache for DataGridRow objects to avoid rebuilding unchanged rows
  final Map<int, DataGridRow> _rowCache = {};

  EditorDataSource({
    required this.onCellEdit,
    required this.onCellTap,
    required this.onCheckboxTap,
    required this.isRowSelected,
  });

  /// Update the data rows
  /// Performance: Only notifies listeners if data actually changed
  void updateDataSource(List<TranslationRow> rows) {
    if (_rows == rows) return; // Early exit if data hasn't changed
    _rows = rows;
    _rowCache.clear(); // Clear cache when data changes
    notifyListeners();
  }

  /// Get all translation row data
  List<TranslationRow> get translationRows => _rows;

  /// Get all unit IDs
  List<String> get allUnitIds => _rows.map((row) => row.id).toList();

  /// Notify listeners to refresh display (e.g., after selection change)
  void refreshDisplay() {
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows.asMap().entries.map((entry) {
    final index = entry.key;
    final row = entry.value;

    // Performance: Use cached row if available
    return _rowCache.putIfAbsent(index, () {
      return DataGridRow(
        cells: [
          DataGridCell<String>(
            columnName: 'checkbox',
            value: row.id,
          ),
          DataGridCell<TranslationVersionStatus>(
            columnName: 'status',
            value: row.status,
          ),
          DataGridCell<String?>(
            columnName: 'locFile',
            value: row.sourceLocFile,
          ),
          DataGridCell<String>(
            columnName: 'key',
            value: row.key,
          ),
          DataGridCell<String>(
            columnName: 'sourceText',
            value: row.sourceText,
          ),
          DataGridCell<String?>(
            columnName: 'translatedText',
            value: row.translatedText,
          ),
          DataGridCell<String>(
            columnName: 'tmSource',
            value: _getTmSourceText(row),
          ),
          DataGridCell<double?>(
            columnName: 'confidence',
            value: row.confidence,
          ),
          DataGridCell<String>(
            columnName: 'actions',
            value: row.id,
          ),
        ],
      );
    });
  }).toList();

  // Performance: Static method to avoid closure allocation
  static String _getTmSourceText(TranslationRow row) {
    if (row.isManuallyEdited) return 'Manual';
    
    // Use explicit translation source field if available
    switch (row.translationSource) {
      case TranslationSource.tmExact:
        return 'Exact Match';
      case TranslationSource.tmFuzzy:
        return 'Fuzzy Match';
      case TranslationSource.llm:
        return 'LLM';
      case TranslationSource.manual:
        return 'Manual';
      case TranslationSource.unknown:
        // Fallback for legacy data: use confidence-based detection
        if (row.confidence != null) {
          if (row.confidence! >= 0.999) return 'Exact Match';
          if (row.confidence! >= 0.85) return 'Fuzzy Match';
          return 'LLM';
        }
        return 'None';
    }
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final checkboxCell = row.getCells()[0];
    final statusCell = row.getCells()[1];
    final locFileCell = row.getCells()[2];
    final keyCell = row.getCells()[3];
    final sourceTextCell = row.getCells()[4];
    final translatedTextCell = row.getCells()[5];
    final tmSourceCell = row.getCells()[6];
    final confidenceCell = row.getCells()[7];

    final unitId = checkboxCell.value as String;
    final isSelected = isRowSelected(unitId);

    // Performance: Wrap cells in RepaintBoundary except multiline text cells
    // which need to expand freely
    return DataGridRowAdapter(
      cells: [
        RepaintBoundary(
          child: CheckboxCellRenderer(
            isSelected: isSelected,
            onTap: () => onCheckboxTap(unitId),
          ),
        ),
        RepaintBoundary(child: StatusCellRenderer(status: statusCell.value)),
        RepaintBoundary(child: TextCellRenderer(text: _extractLocFileName(locFileCell.value), isKey: true)),
        RepaintBoundary(child: TextCellRenderer(text: keyCell.value, isKey: true)),
        // Don't wrap multiline text cells in RepaintBoundary to allow proper height expansion
        TextCellRenderer(text: sourceTextCell.value),
        TextCellRenderer(text: translatedTextCell.value),
        RepaintBoundary(child: TextCellRenderer(text: tmSourceCell.value)),
        RepaintBoundary(child: ConfidenceCellRenderer(confidence: confidenceCell.value)),
      ],
    );
  }

  /// Extract just the filename from the full .loc file path
  static String? _extractLocFileName(String? path) {
    if (path == null || path.isEmpty) return null;
    final lastSeparator = path.lastIndexOf('/');
    if (lastSeparator == -1) return path;
    return path.substring(lastSeparator + 1);
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      alignment: Alignment.centerLeft,
      child: TextField(
        autofocus: true,
        controller: TextEditingController(text: escapedText),
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
