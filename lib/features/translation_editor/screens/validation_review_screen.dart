import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../../providers/batch/batch_operations_provider.dart';
import '../widgets/validation_review_data_source.dart';
import '../widgets/validation_review_header.dart';
import '../widgets/validation_review_inspector_panel.dart';
import '../widgets/validation_review_toolbar.dart';
import '../widgets/validation_edit_dialog.dart';

/// Full-screen validation review with DataGrid for efficient handling of many issues.
class ValidationReviewScreen extends ConsumerStatefulWidget {
  final List<ValidationIssue> issues;
  final int totalValidated;
  final int passedCount;
  final Future<void> Function(ValidationIssue issue) onRejectTranslation;
  final Future<void> Function(ValidationIssue issue) onAcceptTranslation;
  final Future<void> Function(List<ValidationIssue> issues)?
      onBulkAcceptTranslation;
  final Future<void> Function(List<ValidationIssue> issues)?
      onBulkRejectTranslation;
  final Future<void> Function(ValidationIssue issue, String newText)?
      onEditTranslation;
  final Future<void> Function(String filePath, List<ValidationIssue> issues)?
      onExportReport;
  final VoidCallback? onClose;

  const ValidationReviewScreen({
    super.key,
    required this.issues,
    required this.totalValidated,
    required this.passedCount,
    required this.onRejectTranslation,
    required this.onAcceptTranslation,
    this.onBulkAcceptTranslation,
    this.onBulkRejectTranslation,
    this.onEditTranslation,
    this.onExportReport,
    this.onClose,
  });

  @override
  ConsumerState<ValidationReviewScreen> createState() =>
      _ValidationReviewScreenState();
}

class _ValidationReviewScreenState
    extends ConsumerState<ValidationReviewScreen> {
  late ValidationReviewDataSource _dataSource;
  final DataGridController _controller = DataGridController();
  final Set<String> _selectedVersionIds = {};
  final Set<String> _processedVersionIds = {};
  final Set<String> _processingVersionIds = {};
  String? _currentVersionId;
  final FocusNode _gridFocusNode = FocusNode(debugLabel: 'ValidationReviewGrid');
  ValidationSeverityFilter _severityFilter = ValidationSeverityFilter.all;
  String _searchQuery = '';

  List<ValidationIssue> get _activeIssues {
    return widget.issues
        .where((issue) => !_processedVersionIds.contains(issue.versionId))
        .toList();
  }

  List<ValidationIssue> get _filteredIssues {
    var issues = _activeIssues;

    // Apply severity filter
    switch (_severityFilter) {
      case ValidationSeverityFilter.errorsOnly:
        issues = issues
            .where((i) => i.severity == ValidationSeverity.error)
            .toList();
        break;
      case ValidationSeverityFilter.warningsOnly:
        issues = issues
            .where((i) => i.severity == ValidationSeverity.warning)
            .toList();
        break;
      case ValidationSeverityFilter.all:
        break;
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      issues = issues.where((issue) {
        return issue.unitKey.toLowerCase().contains(query) ||
            issue.sourceText.toLowerCase().contains(query) ||
            issue.translatedText.toLowerCase().contains(query) ||
            issue.description.toLowerCase().contains(query);
      }).toList();
    }

    return issues;
  }

  @override
  void initState() {
    super.initState();
    _dataSource = ValidationReviewDataSource(
      issues: _filteredIssues,
      isRowSelected: (versionId) => _selectedVersionIds.contains(versionId),
      onCheckboxTap: _handleCheckboxTap,
    );
  }

  @override
  void dispose() {
    _gridFocusNode.dispose();
    super.dispose();
  }

  void _updateDataSource() {
    _dataSource.updateIssues(
      _filteredIssues,
      isRowSelected: (versionId) => _selectedVersionIds.contains(versionId),
    );
  }

  void _handleCheckboxTap(String versionId) {
    setState(() {
      if (_selectedVersionIds.contains(versionId)) {
        _selectedVersionIds.remove(versionId);
      } else {
        _selectedVersionIds.add(versionId);
      }
    });
    _updateDataSource();
  }

  void _selectCurrentRow(String versionId) {
    if (_currentVersionId == versionId) return;
    setState(() => _currentVersionId = versionId);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final int delta;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      delta = 1;
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      delta = -1;
    } else {
      return KeyEventResult.ignored;
    }

    final issues = _filteredIssues;
    if (issues.isEmpty) return KeyEventResult.ignored;

    final currentIndex =
        issues.indexWhere((i) => i.versionId == _currentVersionId);
    if (currentIndex < 0) return KeyEventResult.ignored;

    final newIndex = (currentIndex + delta).clamp(0, issues.length - 1);
    if (newIndex == currentIndex) return KeyEventResult.handled;

    _selectCurrentRow(issues[newIndex].versionId);
    return KeyEventResult.handled;
  }

  void _selectAll() {
    setState(() {
      _selectedVersionIds.clear();
      _selectedVersionIds.addAll(_filteredIssues.map((i) => i.versionId));
    });
    _updateDataSource();
  }

  void _deselectAll() {
    setState(() {
      _selectedVersionIds.clear();
    });
    _updateDataSource();
  }

  Future<void> _handleAccept(ValidationIssue issue) async {
    setState(() => _processingVersionIds.add(issue.versionId));
    _updateDataSource();

    try {
      await widget.onAcceptTranslation(issue);
      setState(() {
        _processedVersionIds.add(issue.versionId);
        _selectedVersionIds.remove(issue.versionId);
      });
    } finally {
      setState(() => _processingVersionIds.remove(issue.versionId));
      _updateDataSource();
    }
  }

  Future<void> _handleReject(ValidationIssue issue) async {
    setState(() => _processingVersionIds.add(issue.versionId));
    _updateDataSource();

    try {
      await widget.onRejectTranslation(issue);
      setState(() {
        _processedVersionIds.add(issue.versionId);
        _selectedVersionIds.remove(issue.versionId);
      });
    } finally {
      setState(() => _processingVersionIds.remove(issue.versionId));
      _updateDataSource();
    }
  }

  Future<void> _handleEdit(ValidationIssue issue) async {
    if (widget.onEditTranslation == null) return;

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => ValidationEditDialog(issue: issue),
    );

    if (result != null && mounted) {
      setState(() => _processingVersionIds.add(issue.versionId));
      _updateDataSource();

      try {
        await widget.onEditTranslation!(issue, result);
        setState(() {
          _processedVersionIds.add(issue.versionId);
          _selectedVersionIds.remove(issue.versionId);
        });
      } finally {
        setState(() => _processingVersionIds.remove(issue.versionId));
        _updateDataSource();
      }
    }
  }

  Future<void> _handleBulkAccept() async {
    final selectedIssues = _filteredIssues
        .where((i) => _selectedVersionIds.contains(i.versionId))
        .toList();

    if (selectedIssues.isEmpty) return;

    // Mark all as processing
    setState(() {
      for (final issue in selectedIssues) {
        _processingVersionIds.add(issue.versionId);
      }
    });
    _updateDataSource();

    try {
      if (widget.onBulkAcceptTranslation != null) {
        // Use batch operation for all selected issues at once
        await widget.onBulkAcceptTranslation!(selectedIssues);
      } else {
        // Fallback to individual calls
        for (final issue in selectedIssues) {
          await widget.onAcceptTranslation(issue);
        }
      }
      setState(() {
        for (final issue in selectedIssues) {
          _processedVersionIds.add(issue.versionId);
          _selectedVersionIds.remove(issue.versionId);
        }
      });
    } finally {
      setState(() {
        for (final issue in selectedIssues) {
          _processingVersionIds.remove(issue.versionId);
        }
      });
      _updateDataSource();
    }
  }

  Future<void> _handleBulkReject() async {
    final selectedIssues = _filteredIssues
        .where((i) => _selectedVersionIds.contains(i.versionId))
        .toList();

    if (selectedIssues.isEmpty) return;

    // Mark all as processing
    setState(() {
      for (final issue in selectedIssues) {
        _processingVersionIds.add(issue.versionId);
      }
    });
    _updateDataSource();

    try {
      if (widget.onBulkRejectTranslation != null) {
        // Use batch operation for all selected issues at once
        await widget.onBulkRejectTranslation!(selectedIssues);
      } else {
        // Fallback to individual calls
        for (final issue in selectedIssues) {
          await widget.onRejectTranslation(issue);
        }
      }
      setState(() {
        for (final issue in selectedIssues) {
          _processedVersionIds.add(issue.versionId);
          _selectedVersionIds.remove(issue.versionId);
        }
      });
    } finally {
      setState(() {
        for (final issue in selectedIssues) {
          _processingVersionIds.remove(issue.versionId);
        }
      });
      _updateDataSource();
    }
  }

  Future<void> _exportReport() async {
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Validation Report',
      fileName: 'validation_report.txt',
      type: FileType.custom,
      allowedExtensions: ['txt', 'csv'],
    );

    if (result != null && widget.onExportReport != null) {
      await widget.onExportReport!(result, _activeIssues);
      if (mounted) {
        FluentToast.success(context, 'Validation report exported');
      }
    }
  }

  void _setFilter(ValidationSeverityFilter filter) {
    setState(() {
      _severityFilter = filter;
      _selectedVersionIds.clear();
      _pruneStaleCurrentIfFiltered();
    });
    _updateDataSource();
  }

  /// Clears `_currentVersionId` when it refers to a row that is no longer
  /// visible under the active filters, so the inspector and keyboard
  /// navigation stay consistent with what is shown.
  void _pruneStaleCurrentIfFiltered() {
    if (_currentVersionId == null) return;
    final stillVisible = _filteredIssues.any(
      (i) => i.versionId == _currentVersionId,
    );
    if (!stillVisible) _currentVersionId = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorCount =
        _activeIssues.where((i) => i.severity == ValidationSeverity.error).length;
    final warningCount =
        _activeIssues.where((i) => i.severity == ValidationSeverity.warning).length;
    final currentPassedCount = widget.passedCount + _processedVersionIds.length;

    final currentIssueIndex = _currentVersionId == null
        ? -1
        : _filteredIssues.indexWhere((i) => i.versionId == _currentVersionId);
    final currentIssue =
        currentIssueIndex >= 0 ? _filteredIssues[currentIssueIndex] : null;
    final isCurrentProcessing = _currentVersionId != null &&
        _processingVersionIds.contains(_currentVersionId);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // Header
          ValidationReviewHeader(
            totalValidated: widget.totalValidated,
            activeIssuesCount: _activeIssues.length,
            errorCount: errorCount,
            warningCount: warningCount,
            passedCount: currentPassedCount,
            reviewedCount: _processedVersionIds.length,
            onExport: _exportReport,
            onClose: widget.onClose,
          ),

          // Toolbar
          ValidationReviewToolbar(
            severityFilter: _severityFilter,
            selectedCount: _selectedVersionIds.length,
            onFilterChanged: _setFilter,
            onSearchChanged: (value) {
              setState(() {
                _searchQuery = value;
                _pruneStaleCurrentIfFiltered();
              });
              _updateDataSource();
            },
            onSelectAll: _selectAll,
            onDeselectAll: _deselectAll,
            onBulkAccept: _handleBulkAccept,
            onBulkReject: _handleBulkReject,
          ),

          // DataGrid
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _filteredIssues.isEmpty
                      ? _buildEmptyState(theme)
                      : _buildDataGrid(theme),
                ),
                ValidationReviewInspectorPanel(
                  currentIssue: currentIssue,
                  currentIndex:
                      currentIssue == null ? null : currentIssueIndex + 1,
                  total: _filteredIssues.length,
                  isProcessing: isCurrentProcessing,
                  onEdit: currentIssue == null
                      ? () {}
                      : () => _handleEdit(currentIssue),
                  onAccept: currentIssue == null
                      ? () {}
                      : () => _handleAccept(currentIssue),
                  onReject: currentIssue == null
                      ? () {}
                      : () => _handleReject(currentIssue),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataGrid(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Focus(
            focusNode: _gridFocusNode,
            onKeyEvent: _handleKeyEvent,
            child: SfDataGrid(
              source: _dataSource,
              controller: _controller,
              columnWidthMode: ColumnWidthMode.fill,
              gridLinesVisibility: GridLinesVisibility.both,
              headerGridLinesVisibility: GridLinesVisibility.both,
              allowSorting: true,
              allowColumnsResizing: true,
              columnResizeMode: ColumnResizeMode.onResize,
              rowHeight: 44,
              headerRowHeight: 30,
              columns: [
                GridColumn(
                  columnName: 'checkbox',
                  width: 50,
                  allowSorting: false,
                  label: _buildCheckboxHeaderCell(theme),
                ),
                GridColumn(
                  columnName: 'severity',
                  width: 100,
                  label: _buildHeaderCell(theme, 'Severity'),
                ),
                GridColumn(
                  columnName: 'issueType',
                  width: 140,
                  label: _buildHeaderCell(theme, 'Issue Type'),
                ),
                GridColumn(
                  columnName: 'key',
                  width: 200,
                  label: _buildHeaderCell(theme, 'Key'),
                ),
                GridColumn(
                  columnName: 'description',
                  width: 250,
                  label: _buildHeaderCell(theme, 'Description'),
                ),
                GridColumn(
                  columnName: 'sourceText',
                  minimumWidth: 200,
                  label: _buildHeaderCell(theme, 'Source Text'),
                ),
                GridColumn(
                  columnName: 'translatedText',
                  minimumWidth: 200,
                  label: _buildHeaderCell(theme, 'Translation'),
                ),
              ],
              onCellTap: (details) {
                if (details.rowColumnIndex.rowIndex == 0) return; // header row
                final rowIndex = details.rowColumnIndex.rowIndex - 1;
                if (rowIndex < 0 || rowIndex >= _filteredIssues.length) return;

                final issue = _filteredIssues[rowIndex];
                if (details.column.columnName == 'checkbox') {
                  _handleCheckboxTap(issue.versionId);
                  return;
                }
                _selectCurrentRow(issue.versionId);
                _gridFocusNode.requestFocus();
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCell(ThemeData theme, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.centerLeft,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildCheckboxHeaderCell(ThemeData theme) {
    final allSelected = _filteredIssues.isNotEmpty &&
        _selectedVersionIds.length == _filteredIssues.length;
    final someSelected = _selectedVersionIds.isNotEmpty &&
        _selectedVersionIds.length < _filteredIssues.length;

    return Container(
      alignment: Alignment.center,
      color: theme.colorScheme.surfaceContainerHighest,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            if (allSelected) {
              _deselectAll();
            } else {
              _selectAll();
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: allSelected || someSelected
                  ? theme.colorScheme.primary
                  : Colors.transparent,
              border: Border.all(
                color: allSelected || someSelected
                    ? theme.colorScheme.primary
                    : theme.dividerColor,
                width: 2,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: allSelected
                ? const Icon(
                    FluentIcons.checkmark_12_filled,
                    size: 14,
                    color: Colors.white,
                  )
                : someSelected
                    ? const Icon(
                        FluentIcons.subtract_12_filled,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final allReviewed = _processedVersionIds.length == widget.issues.length;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            size: 64,
            color: Colors.green[700],
          ),
          const SizedBox(height: 16),
          Text(
            allReviewed
                ? 'All issues have been reviewed!'
                : 'No validation issues found!',
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.green[700],
            ),
          ),
          if (_processedVersionIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${_processedVersionIds.length} issue(s) reviewed',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          FluentButton(
            onPressed: () {
              if (widget.onClose != null) {
                widget.onClose!();
              } else {
                context.pop();
              }
            },
            icon: const Icon(FluentIcons.arrow_left_24_regular),
            child: const Text('Back to Editor'),
          ),
        ],
      ),
    );
  }
}
