import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/services/translation/models/validation_rule.dart';
import '../../../providers/batch/batch_operations_provider.dart';

/// DataSource for validation review DataGrid
class ValidationReviewDataSource extends DataGridSource {
  List<ValidationIssue> _issues = [];
  bool Function(String versionId) _isRowSelected;
  final Function(String versionId) onCheckboxTap;

  ValidationReviewDataSource({
    required List<ValidationIssue> issues,
    required bool Function(String versionId) isRowSelected,
    required this.onCheckboxTap,
  })  : _issues = issues,
        _isRowSelected = isRowSelected;

  void updateIssues(
    List<ValidationIssue> issues, {
    required bool Function(String versionId) isRowSelected,
  }) {
    _issues = issues;
    _isRowSelected = isRowSelected;
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _issues.map((issue) {
        return DataGridRow(cells: [
          DataGridCell<String>(columnName: 'checkbox', value: issue.versionId),
          DataGridCell<ValidationSeverity>(
            columnName: 'severity',
            value: issue.severity,
          ),
          DataGridCell<String>(columnName: 'issueType', value: issue.issueType),
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
    final versionId = row.getCells()[0].value as String;
    final severity = row.getCells()[1].value as ValidationSeverity;
    final issueType = row.getCells()[2].value as String;
    final key = row.getCells()[3].value as String;
    final description = row.getCells()[4].value as String;
    final sourceText = row.getCells()[5].value as String;
    final translatedText = row.getCells()[6].value as String;

    final isSelected = _isRowSelected(versionId);

    return DataGridRowAdapter(
      color: isSelected ? Colors.blue.withValues(alpha: 0.08) : null,
      cells: [
        _buildCheckboxCell(versionId, isSelected),
        _buildSeverityCell(severity),
        _buildIssueTypeCell(issueType, severity),
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

  Widget _buildSeverityCell(ValidationSeverity severity) {
    final isError = severity == ValidationSeverity.error;
    final color = isError ? Colors.red[700]! : Colors.orange[700]!;
    final icon = isError
        ? FluentIcons.error_circle_24_filled
        : FluentIcons.warning_24_filled;
    final label = isError ? 'Error' : 'Warning';

    return Builder(builder: (context) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: label,
          child: Icon(icon, size: 16, color: color),
        ),
      );
    });
  }

  Widget _buildIssueTypeCell(String issueType, ValidationSeverity severity) {
    final label = _labelForIssueType(issueType);
    final isError = severity == ValidationSeverity.error;
    final color = isError ? Colors.red[700]! : Colors.orange[700]!;

    return Builder(builder: (context) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      );
    });
  }

  /// Humanise the `issueType` rule code for the "Issue Type" column.
  ///
  /// Rows that pre-date structured persistence surface as `legacy`; the
  /// label reflects that so the user can see they are pending a rescan.
  String _labelForIssueType(String code) {
    if (code == 'legacy') return 'Legacy';
    final rule = ValidationRule.fromCodeName(code);
    return rule?.label ?? code;
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
