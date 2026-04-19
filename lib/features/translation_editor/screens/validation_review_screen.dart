import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
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
  final FocusNode _gridFocusNode = FocusNode(
    debugLabel: 'ValidationReviewGrid',
  );
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

  /// Replaces the bulk selection with a single row. Called by non-checkbox
  /// cell taps and by arrow-key navigation. The editor uses the same pattern:
  /// clicking a row clears the multi-selection and single-selects it.
  void _singleSelectRow(String versionId) {
    setState(() {
      _selectedVersionIds
        ..clear()
        ..add(versionId);
    });
    _updateDataSource();
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

    // Arrow keys only nudge a *single* selection. Multi/zero selections
    // fall through to let the user click or Ctrl+A first.
    if (_selectedVersionIds.length != 1) return KeyEventResult.ignored;

    final currentId = _selectedVersionIds.first;
    final currentIndex = issues.indexWhere((i) => i.versionId == currentId);
    if (currentIndex < 0) return KeyEventResult.ignored;

    final newIndex = (currentIndex + delta).clamp(0, issues.length - 1);
    if (newIndex == currentIndex) return KeyEventResult.handled;

    _singleSelectRow(issues[newIndex].versionId);
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
      // Changing the severity filter wholesale is treated like "pick a fresh
      // review queue" — drop the bulk selection so the next batch Accept/Reject
      // operates on the new visible set, not on stale ids that happen to still
      // match.
      _selectedVersionIds.clear();
    });
    _updateDataSource();
  }

  /// Removes ids from `_selectedVersionIds` that are no longer in the
  /// filtered set, so the inspector and keyboard navigation stay consistent
  /// with what is shown. Called from search-change (filter-change already
  /// wipes the selection wholesale).
  void _pruneSelectionToFilteredSet() {
    final visible = _filteredIssues.map((i) => i.versionId).toSet();
    _selectedVersionIds.removeWhere((id) => !visible.contains(id));
  }

  /// Ctrl+A handler: toggle bulk selection (`_selectedVersionIds`) over every
  /// issue currently visible in the DataGrid (after severity + search filters).
  ///
  /// - No selection -> select every filtered issue.
  /// - Partial selection -> expand to every filtered issue.
  /// - Every filtered issue already selected -> clear - giving Ctrl+A a
  ///   familiar toggle feel.
  void _toggleSelectAllFilteredIssues() {
    final ids = _filteredIssues.map((i) => i.versionId).toList();
    if (ids.isEmpty) return;

    final allSelected = ids.every((id) => _selectedVersionIds.contains(id));

    setState(() {
      _selectedVersionIds.clear();
      if (!allSelected) {
        _selectedVersionIds.addAll(ids);
      }
    });
    _updateDataSource();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorCount = _activeIssues
        .where((i) => i.severity == ValidationSeverity.error)
        .length;
    final warningCount = _activeIssues
        .where((i) => i.severity == ValidationSeverity.warning)
        .length;
    final currentPassedCount = widget.passedCount + _processedVersionIds.length;

    final selectedCount = _selectedVersionIds.length;
    final String? singleSelectedId = selectedCount == 1
        ? _selectedVersionIds.first
        : null;
    final singleSelectedIndex = singleSelectedId == null
        ? -1
        : _filteredIssues.indexWhere((i) => i.versionId == singleSelectedId);
    final singleSelectedIssue = singleSelectedIndex >= 0
        ? _filteredIssues[singleSelectedIndex]
        : null;
    final isSingleSelectedProcessing =
        singleSelectedId != null &&
        _processingVersionIds.contains(singleSelectedId);

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyA):
            const _SelectAllIssuesIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SelectAllIssuesIntent: _SelectAllIssuesAction(
            _toggleSelectAllFilteredIssues,
          ),
        },
        // Autofocus anchor so the Shortcuts map is live the moment the screen
        // mounts. Without it, `Shortcuts` only fires after the user clicks a
        // focusable child. `skipTraversal: true` keeps this node out of Tab
        // focus traversal.
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: Scaffold(
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
                      _pruneSelectionToFilteredSet();
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
                        currentIssue: singleSelectedIssue,
                        currentIndex: singleSelectedIssue == null
                            ? null
                            : singleSelectedIndex + 1,
                        total: _filteredIssues.length,
                        isProcessing: isSingleSelectedProcessing,
                        selectedCount: selectedCount,
                        onEdit: singleSelectedIssue == null
                            ? () {}
                            : () => _handleEdit(singleSelectedIssue),
                        onAccept: singleSelectedIssue == null
                            ? () {}
                            : () => _handleAccept(singleSelectedIssue),
                        onReject: singleSelectedIssue == null
                            ? () {}
                            : () => _handleReject(singleSelectedIssue),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataGrid(ThemeData theme) {
    // Token-aware selected-row tint, plumbed in every build like the editor
    // grid (see editor_datagrid.dart `setSelectedRowColor`).
    _dataSource.setSelectedRowColor(context.tokens.accentBg);

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
                  columnName: 'key',
                  width: 200,
                  label: _buildHeaderCell(theme, 'Key'),
                ),
                GridColumn(
                  columnName: 'description',
                  minimumWidth: 200,
                  label: _buildHeaderCell(theme, 'Issue'),
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
                _singleSelectRow(issue.versionId);
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
    final allSelected =
        _filteredIssues.isNotEmpty &&
        _selectedVersionIds.length == _filteredIssues.length;
    final someSelected =
        _selectedVersionIds.isNotEmpty &&
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

class _SelectAllIssuesIntent extends Intent {
  const _SelectAllIssuesIntent();
}

/// Action for [_SelectAllIssuesIntent] that declines the key event when focus
/// sits inside an [EditableText]. Returning `false` from [consumesKey] makes
/// the enclosing `Shortcuts` widget report `KeyEventResult.ignored`, so the
/// native Ctrl+A "select all text" behaviour keeps working while the user is
/// typing in the toolbar search field.
class _SelectAllIssuesAction extends Action<_SelectAllIssuesIntent> {
  _SelectAllIssuesAction(this._onInvoke);

  final VoidCallback _onInvoke;

  static bool _focusIsInTextInput() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  bool consumesKey(_SelectAllIssuesIntent intent) => !_focusIsInTextInput();

  @override
  Object? invoke(_SelectAllIssuesIntent intent) {
    if (_focusIsInTextInput()) return null;
    _onInvoke();
    return null;
  }
}
