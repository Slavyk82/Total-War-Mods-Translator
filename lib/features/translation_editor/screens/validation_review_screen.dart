import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import '../../../providers/batch/batch_operations_provider.dart';
import '../widgets/validation_review_data_source.dart';

/// Full-screen validation review with DataGrid for efficient handling of many issues
class ValidationReviewScreen extends ConsumerStatefulWidget {
  final List<ValidationIssue> issues;
  final int totalValidated;
  final int passedCount;
  final Future<void> Function(ValidationIssue issue) onRejectTranslation;
  final Future<void> Function(ValidationIssue issue) onAcceptTranslation;
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
      isProcessing: (versionId) => _processingVersionIds.contains(versionId),
      onCheckboxTap: _handleCheckboxTap,
    );
    // Connect action callbacks
    _dataSource.onAccept = _handleAccept;
    _dataSource.onReject = _handleReject;
    _dataSource.onEdit = _handleEdit;
  }

  void _updateDataSource() {
    _dataSource.updateIssues(
      _filteredIssues,
      isRowSelected: (versionId) => _selectedVersionIds.contains(versionId),
      isProcessing: (versionId) => _processingVersionIds.contains(versionId),
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
      builder: (dialogContext) => _EditTranslationDialog(
        issue: issue,
      ),
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

    for (final issue in selectedIssues) {
      await _handleAccept(issue);
    }
  }

  Future<void> _handleBulkReject() async {
    final selectedIssues = _filteredIssues
        .where((i) => _selectedVersionIds.contains(i.versionId))
        .toList();

    for (final issue in selectedIssues) {
      await _handleReject(issue);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorCount =
        _activeIssues.where((i) => i.severity == ValidationSeverity.error).length;
    final warningCount =
        _activeIssues.where((i) => i.severity == ValidationSeverity.warning).length;
    final currentPassedCount = widget.passedCount + _processedVersionIds.length;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Column(
        children: [
          // Header
          _buildHeader(theme, errorCount, warningCount, currentPassedCount),

          // Toolbar
          _buildToolbar(theme),

          // DataGrid
          Expanded(
            child: _filteredIssues.isEmpty
                ? _buildEmptyState(theme)
                : _buildDataGrid(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    ThemeData theme,
    int errorCount,
    int warningCount,
    int passedCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row with back button
          Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else {
                      context.pop();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: theme.dividerColor),
                    ),
                    child: Icon(
                      FluentIcons.arrow_left_24_regular,
                      size: 20,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                FluentIcons.shield_checkmark_24_regular,
                size: 28,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Text(
                'Validation Review',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FluentTextButton(
                onPressed: _exportReport,
                icon: const Icon(FluentIcons.document_arrow_down_24_regular),
                child: const Text('Export Report'),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Summary cards
          Row(
            children: [
              _buildSummaryCard(
                theme,
                'Total Validated',
                '${widget.totalValidated}',
                FluentIcons.checkmark_circle_24_regular,
                theme.colorScheme.primary,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                theme,
                'Issues Found',
                '${_activeIssues.length}',
                FluentIcons.info_24_regular,
                Colors.blue[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                theme,
                'Errors',
                '$errorCount',
                FluentIcons.error_circle_24_regular,
                Colors.red[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                theme,
                'Warnings',
                '$warningCount',
                FluentIcons.warning_24_regular,
                Colors.orange[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                theme,
                'Passed',
                '$passedCount',
                FluentIcons.checkmark_24_regular,
                Colors.green[700]!,
              ),
              const SizedBox(width: 16),
              _buildSummaryCard(
                theme,
                'Reviewed',
                '${_processedVersionIds.length}',
                FluentIcons.clipboard_checkmark_24_regular,
                Colors.purple[700]!,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolbar(ThemeData theme) {
    final hasSelection = _selectedVersionIds.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          // Filter chips
          _buildFilterChip(
            theme,
            'All',
            null,
            _severityFilter == ValidationSeverityFilter.all,
            () => _setFilter(ValidationSeverityFilter.all),
            theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            theme,
            'Errors',
            FluentIcons.error_circle_24_regular,
            _severityFilter == ValidationSeverityFilter.errorsOnly,
            () => _setFilter(ValidationSeverityFilter.errorsOnly),
            Colors.red[700]!,
          ),
          const SizedBox(width: 8),
          _buildFilterChip(
            theme,
            'Warnings',
            FluentIcons.warning_24_regular,
            _severityFilter == ValidationSeverityFilter.warningsOnly,
            () => _setFilter(ValidationSeverityFilter.warningsOnly),
            Colors.orange[700]!,
          ),

          const SizedBox(width: 24),

          // Search
          SizedBox(
            width: 300,
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by key, text, or description...',
                prefixIcon: const Icon(FluentIcons.search_24_regular, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: theme.dividerColor),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
                _updateDataSource();
              },
            ),
          ),

          const Spacer(),

          // Selection info and bulk actions
          if (hasSelection) ...[
            Text(
              '${_selectedVersionIds.length} selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 16),
            _buildActionButton(
              theme,
              'Accept All',
              FluentIcons.checkmark_24_regular,
              Colors.green[700]!,
              _handleBulkAccept,
            ),
            const SizedBox(width: 8),
            _buildActionButton(
              theme,
              'Reject All',
              FluentIcons.dismiss_24_regular,
              Colors.red[700]!,
              _handleBulkReject,
            ),
            const SizedBox(width: 8),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _deselectAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: const Text('Deselect'),
                ),
              ),
            ),
          ] else ...[
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: _selectAll,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        FluentIcons.checkbox_checked_24_regular,
                        size: 16,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      const Text('Select All'),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _setFilter(ValidationSeverityFilter filter) {
    setState(() {
      _severityFilter = filter;
      _selectedVersionIds.clear();
    });
    _updateDataSource();
  }

  Widget _buildFilterChip(
    ThemeData theme,
    String label,
    IconData? icon,
    bool isActive,
    VoidCallback onTap,
    Color color,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? color.withValues(alpha: 0.1)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isActive ? color : theme.dividerColor,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 16,
                  color: isActive ? color : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : theme.colorScheme.onSurface,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(
    ThemeData theme,
    String label,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
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
          child: SfDataGrid(
            source: _dataSource,
            controller: _controller,
            columnWidthMode: ColumnWidthMode.fill,
            gridLinesVisibility: GridLinesVisibility.both,
            headerGridLinesVisibility: GridLinesVisibility.both,
            allowSorting: true,
            allowColumnsResizing: true,
            columnResizeMode: ColumnResizeMode.onResize,
            rowHeight: 80,
            headerRowHeight: 48,
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
              GridColumn(
                columnName: 'actions',
                width: 200,
                allowSorting: false,
                label: _buildHeaderCell(theme, 'Actions'),
              ),
            ],
            onCellTap: (details) {
              if (details.rowColumnIndex.rowIndex > 0 &&
                  details.column.columnName == 'checkbox') {
                final rowIndex = details.rowColumnIndex.rowIndex - 1;
                if (rowIndex < _filteredIssues.length) {
                  _handleCheckboxTap(_filteredIssues[rowIndex].versionId);
                }
              }
            },
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

enum ValidationSeverityFilter { all, errorsOnly, warningsOnly }

/// Dialog for editing a translation manually
class _EditTranslationDialog extends StatefulWidget {
  final ValidationIssue issue;

  const _EditTranslationDialog({required this.issue});

  @override
  State<_EditTranslationDialog> createState() => _EditTranslationDialogState();
}

class _EditTranslationDialogState extends State<_EditTranslationDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.issue.translatedText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: 800,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  FluentIcons.edit_24_regular,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Edit Translation',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.issue.unitKey,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(
                      FluentIcons.dismiss_24_regular,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Issue description
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.issue.severity == ValidationSeverity.error
                    ? Colors.red.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.issue.severity == ValidationSeverity.error
                      ? Colors.red.withValues(alpha: 0.3)
                      : Colors.orange.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.issue.severity == ValidationSeverity.error
                        ? FluentIcons.error_circle_24_regular
                        : FluentIcons.warning_24_regular,
                    size: 20,
                    color: widget.issue.severity == ValidationSeverity.error
                        ? Colors.red[700]
                        : Colors.orange[700],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.issue.issueType}: ${widget.issue.description}',
                      style: TextStyle(
                        fontSize: 13,
                        color: widget.issue.severity == ValidationSeverity.error
                            ? Colors.red[700]
                            : Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Source text (read-only)
            Text(
              'Source Text',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: theme.dividerColor),
              ),
              child: SelectableText(
                widget.issue.sourceText,
                style: theme.textTheme.bodyMedium,
              ),
            ),

            const SizedBox(height: 16),

            // Translation text (editable)
            Text(
              'Translation',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: TextField(
                controller: _controller,
                maxLines: null,
                minLines: 4,
                decoration: InputDecoration(
                  hintText: 'Enter corrected translation...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: theme.dividerColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                FluentTextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 12),
                FluentButton(
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isNotEmpty) {
                      Navigator.of(context).pop(text);
                    }
                  },
                  icon: const Icon(FluentIcons.checkmark_24_regular),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
