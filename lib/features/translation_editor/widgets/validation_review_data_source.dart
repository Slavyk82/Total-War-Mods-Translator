import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import '../../../providers/batch/batch_operations_provider.dart';

/// DataSource for validation review DataGrid
class ValidationReviewDataSource extends DataGridSource {
  List<ValidationIssue> _issues = [];
  final Map<String, ValidationIssue> _issuesById = {};
  bool Function(String versionId) _isRowSelected;
  final Function(String versionId) onCheckboxTap;
  Color _selectedRowColor = Colors.blue.withValues(alpha: 0.08);

  ValidationReviewDataSource({
    required List<ValidationIssue> issues,
    required bool Function(String versionId) isRowSelected,
    required this.onCheckboxTap,
  })  : _issues = issues,
        _isRowSelected = isRowSelected {
    _issuesById
      ..clear()
      ..addEntries(issues.map((i) => MapEntry(i.versionId, i)));
  }

  void updateIssues(
    List<ValidationIssue> issues, {
    required bool Function(String versionId) isRowSelected,
  }) {
    _issues = issues;
    _issuesById
      ..clear()
      ..addEntries(issues.map((i) => MapEntry(i.versionId, i)));
    _isRowSelected = isRowSelected;
    notifyListeners();
  }

  /// Token-aware background colour for selected rows. Plumbed in from the
  /// screen on every build so the data source stays theme-agnostic. Matches
  /// `EditorDataSource.setSelectedRowColor` — does NOT call `notifyListeners`
  /// (which would trigger a debug warning when invoked during build); the
  /// DataGrid's natural next-frame repaint picks up the new colour.
  void setSelectedRowColor(Color color) {
    if (_selectedRowColor == color) return;
    _selectedRowColor = color;
  }

  @override
  List<DataGridRow> get rows => _issues.map((issue) {
        return DataGridRow(cells: [
          DataGridCell<String>(columnName: 'checkbox', value: issue.versionId),
          DataGridCell<String>(columnName: 'key', value: issue.unitKey),
          DataGridCell<String>(
            columnName: 'description',
            value: issue.description,
          ),
          DataGridCell<String>(
            columnName: 'sourceText',
            value: issue.sourceText,
          ),
          DataGridCell<String>(
            columnName: 'translatedText',
            value: issue.translatedText,
          ),
        ]);
      }).toList();

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final versionId = cells[0].value as String;
    final key = cells[1].value as String;
    final description = cells[2].value as String;
    final sourceText = cells[3].value as String;
    final translatedText = cells[4].value as String;
    final severity = _issuesById[versionId]!.severity;

    final isSelected = _isRowSelected(versionId);

    return DataGridRowAdapter(
      color: isSelected ? _selectedRowColor : null,
      cells: [
        _buildCheckboxCell(versionId, isSelected),
        _buildTextCell(key, isKey: true),
        _buildTextCell(description),
        _buildTextCell(sourceText),
        _buildTextCell(translatedText, isHighlighted: true, severity: severity),
      ],
    );
  }

  Widget _buildCheckboxCell(String versionId, bool isSelected) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onCheckboxTap(versionId),
          child: Container(
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.primary
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.dividerColor,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: isSelected
                  ? const Icon(
                      FluentIcons.checkmark_12_filled,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      );
    });
  }

  Widget _buildTextCell(
    String text, {
    bool isKey = false,
    bool isHighlighted = false,
    ValidationSeverity? severity,
  }) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      Color? backgroundColor;

      if (isHighlighted && severity != null) {
        final isError = severity == ValidationSeverity.error;
        backgroundColor = isError
            ? Colors.red.withValues(alpha: 0.05)
            : Colors.orange.withValues(alpha: 0.05);
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        alignment: Alignment.centerLeft,
        color: backgroundColor,
        child: Text(
          text,
          style: TextStyle(
            fontSize: isKey ? 12 : 13,
            fontFamily: isKey ? 'monospace' : null,
            fontWeight: isKey ? FontWeight.w600 : FontWeight.normal,
            color: theme.colorScheme.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    });
  }

}
