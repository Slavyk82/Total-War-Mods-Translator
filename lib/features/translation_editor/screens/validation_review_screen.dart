import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';
import 'package:twmt/widgets/lists/list_toolbar_leading.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/token_data_grid_header.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import '../../../providers/batch/batch_operations_provider.dart';
import '../providers/editor_providers.dart';
import '../widgets/validation_review_data_source.dart';
import '../widgets/validation_review_inspector_panel.dart';
import '../widgets/validation_edit_dialog.dart';

/// Severity filter for the validation review screen. Matches the editor's
/// filter pill pattern: no pill selected = all issues visible.
enum ValidationSeverityFilter { all, errorsOnly, warningsOnly }

/// Full-screen validation review with DataGrid for efficient handling of many issues.
class ValidationReviewScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
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
    required this.projectId,
    required this.languageId,
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
    // Keep the newly selected row in view. `makeVisible` only nudges the
    // viewport when the row is off-screen, avoiding the jumpy per-step snap
    // (and focus-losing rebuild) that `DataGridScrollPosition.start` causes.
    // Same rationale as `editor_datagrid.dart`.
    _controller.scrollToRow(
      newIndex.toDouble(),
      position: DataGridScrollPosition.makeVisible,
    );
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
    final tokens = context.tokens;
    final errorCount = _activeIssues
        .where((i) => i.severity == ValidationSeverity.error)
        .length;
    final warningCount = _activeIssues
        .where((i) => i.severity == ValidationSeverity.warning)
        .length;
    final currentPassedCount = widget.passedCount + _processedVersionIds.length;

    final projectAsync = ref.watch(currentProjectProvider(widget.projectId));
    final languageAsync = ref.watch(currentLanguageProvider(widget.languageId));
    final projectName = projectAsync.whenOrNull(data: (p) => p.name) ?? '';
    final languageName = languageAsync.whenOrNull(data: (l) => l.name) ?? '';

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

    final activeIssueCount = _activeIssues.length;
    final reviewedCount = _processedVersionIds.length;

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
          child: Material(
            color: tokens.bg,
            child: Column(
              children: [
                DetailScreenToolbar(
                  crumbs: [
                    const CrumbSegment('Work'),
                    const CrumbSegment('Projects', route: AppRoutes.projects),
                    CrumbSegment(
                      projectName,
                      route: AppRoutes.projectDetail(widget.projectId),
                    ),
                    CrumbSegment(languageName),
                    const CrumbSegment('Validation Review'),
                  ],
                  trailing: [
                    if (widget.onExportReport != null)
                      SmallIconButton(
                        icon: FluentIcons.document_arrow_down_24_regular,
                        tooltip: 'Export Report',
                        size: 32,
                        iconSize: 16,
                        onTap: _exportReport,
                      ),
                  ],
                  onBack: () {
                    if (widget.onClose != null) {
                      widget.onClose!();
                    } else if (context.canPop()) {
                      context.pop();
                    } else {
                      Navigator.of(context).maybePop();
                    }
                  },
                ),
                FilterToolbar(
                  leading: ListToolbarLeading(
                    icon: FluentIcons.shield_checkmark_24_regular,
                    title: 'Validation Review',
                    countLabel: '$activeIssueCount issues',
                  ),
                  trailing: [
                    if (selectedCount > 0)
                      _BulkActionCluster(
                        selectedCount: selectedCount,
                        onAccept: _handleBulkAccept,
                        onReject: _handleBulkReject,
                        onDeselect: _deselectAll,
                      ),
                    ListSearchField(
                      value: _searchQuery,
                      hintText: 'Search key · source · target · issue',
                      onChanged: (value) {
                        setState(() {
                          _searchQuery = value;
                          _pruneSelectionToFilteredSet();
                        });
                        _updateDataSource();
                      },
                      onClear: () {
                        setState(() {
                          _searchQuery = '';
                          _pruneSelectionToFilteredSet();
                        });
                        _updateDataSource();
                      },
                    ),
                  ],
                  pillGroups: [
                    _buildSeverityGroup(errorCount, warningCount),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _filteredIssues.isEmpty
                            ? _buildEmptyState()
                            : _buildDataGrid(),
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
                _StatusBar(
                  totalValidated: widget.totalValidated,
                  passedCount: currentPassedCount,
                  reviewedCount: reviewedCount,
                  remainingCount: activeIssueCount,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  FilterPillGroup _buildSeverityGroup(int errorCount, int warningCount) {
    FilterPill pill(
      String label,
      ValidationSeverityFilter filter,
      int count,
    ) {
      final active = _severityFilter == filter;
      return FilterPill(
        label: label,
        selected: active,
        count: count,
        onToggle: () {
          // Toggle-to-clear: re-tapping the active pill returns to 'all',
          // matching how the editor's status pills drop back to "no filter".
          _setFilter(active ? ValidationSeverityFilter.all : filter);
        },
      );
    }

    return FilterPillGroup(
      label: 'SEVERITY',
      clearLabel: 'Clear',
      onClear: () => _setFilter(ValidationSeverityFilter.all),
      pills: [
        pill('Errors', ValidationSeverityFilter.errorsOnly, errorCount),
        pill('Warnings', ValidationSeverityFilter.warningsOnly, warningCount),
      ],
    );
  }

  Widget _buildDataGrid() {
    // Token-aware selected-row tint, plumbed in every build like the editor
    // grid (see editor_datagrid.dart `setSelectedRowColor`).
    _dataSource.setSelectedRowColor(context.tokens.accentBg);

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Focus(
        focusNode: _gridFocusNode,
        onKeyEvent: _handleKeyEvent,
        child: SfDataGridTheme(
          data: buildTokenDataGridTheme(context.tokens),
          child: SfDataGrid(
            source: _dataSource,
            controller: _controller,
            allowEditing: false,
            allowSorting: false,
            allowMultiColumnSorting: false,
            selectionMode: SelectionMode.none,
            navigationMode: GridNavigationMode.row,
            columnWidthMode: ColumnWidthMode.fill,
            gridLinesVisibility: GridLinesVisibility.horizontal,
            headerGridLinesVisibility: GridLinesVisibility.horizontal,
            rowHeight: 44,
            headerRowHeight: 30,
            columns: [
              GridColumn(
                columnName: 'checkbox',
                width: 50,
                allowSorting: false,
                label: _buildCheckboxHeaderCell(),
              ),
              GridColumn(
                columnName: 'key',
                width: 150,
                allowSorting: false,
                label: const TokenDataGridHeader(text: 'KEY'),
              ),
              GridColumn(
                columnName: 'description',
                columnWidthMode: ColumnWidthMode.fill,
                allowSorting: false,
                label: const TokenDataGridHeader(text: 'ISSUE'),
              ),
              GridColumn(
                columnName: 'sourceText',
                columnWidthMode: ColumnWidthMode.fill,
                allowSorting: false,
                label: const TokenDataGridHeader(text: 'SOURCE'),
              ),
              GridColumn(
                columnName: 'translatedText',
                columnWidthMode: ColumnWidthMode.fill,
                allowSorting: false,
                label: const TokenDataGridHeader(text: 'TARGET'),
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
    );
  }

  Widget _buildCheckboxHeaderCell() {
    return Container(
      padding: const EdgeInsets.all(8.0),
      alignment: Alignment.center,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _handleSelectAllCheckbox,
          child: Checkbox(
            value: _getSelectAllCheckboxState(),
            tristate: true,
            onChanged: (_) => _handleSelectAllCheckbox(),
          ),
        ),
      ),
    );
  }

  /// Tri-state for the header checkbox: null = indeterminate (some selected),
  /// true = every filtered row selected, false = none selected. Mirrors the
  /// editor grid's `_getSelectAllCheckboxState`.
  bool? _getSelectAllCheckboxState() {
    if (_selectedVersionIds.isEmpty) return false;
    if (_selectedVersionIds.length == _filteredIssues.length) return true;
    return null;
  }

  void _handleSelectAllCheckbox() {
    if (_getSelectAllCheckboxState() == true) {
      _deselectAll();
    } else {
      _selectAll();
    }
  }

  Widget _buildEmptyState() {
    final tokens = context.tokens;
    final allReviewed = _processedVersionIds.length == widget.issues.length;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            size: 56,
            color: tokens.accent,
          ),
          const SizedBox(height: 16),
          Text(
            allReviewed
                ? 'All issues have been reviewed'
                : 'No validation issues match the current filters',
            style: tokens.fontDisplay.copyWith(
              fontSize: 16,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
            ),
          ),
          if (_processedVersionIds.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${_processedVersionIds.length} issue(s) reviewed',
              style: tokens.fontMono.copyWith(
                fontSize: 12,
                color: tokens.textDim,
              ),
            ),
          ],
          const SizedBox(height: 20),
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

/// Compact bulk-action cluster shown in the `FilterToolbar` trailing slot
/// when at least one issue is checked. Mirrors the tokenised action rail of
/// the editor (panel2 fill, small mono label, accent/err foregrounds).
class _BulkActionCluster extends StatelessWidget {
  const _BulkActionCluster({
    required this.selectedCount,
    required this.onAccept,
    required this.onReject,
    required this.onDeselect,
  });

  final int selectedCount;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onDeselect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$selectedCount selected',
          style: tokens.fontMono.copyWith(
            fontSize: 12,
            color: tokens.textDim,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 10),
        SmallIconButton(
          icon: FluentIcons.checkmark_24_regular,
          tooltip: 'Accept selected',
          size: 32,
          iconSize: 16,
          foreground: tokens.accent,
          onTap: onAccept,
        ),
        const SizedBox(width: 6),
        SmallIconButton(
          icon: FluentIcons.dismiss_24_regular,
          tooltip: 'Reject selected',
          size: 32,
          iconSize: 16,
          foreground: tokens.err,
          onTap: onReject,
        ),
        const SizedBox(width: 6),
        SmallIconButton(
          icon: FluentIcons.dismiss_circle_24_regular,
          tooltip: 'Deselect all',
          size: 32,
          iconSize: 16,
          onTap: onDeselect,
        ),
      ],
    );
  }
}

/// Bottom status bar for the validation review screen. Mirrors
/// [EditorStatusBar]: 28px tall, `panel` fill with a top border, mono-dim
/// labels separated by mid-dot.
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.totalValidated,
    required this.passedCount,
    required this.reviewedCount,
    required this.remainingCount,
  });

  final int totalValidated;
  final int passedCount;
  final int reviewedCount;
  final int remainingCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final monoStyle = tokens.fontMono.copyWith(
      fontSize: 10.5,
      color: tokens.textDim,
      letterSpacing: 0.3,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final accentMonoStyle = monoStyle.copyWith(color: tokens.accent);
    final separator = Text(
      '·',
      style: monoStyle.copyWith(color: tokens.textFaint),
    );
    const gap = SizedBox(width: 22);

    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text('$totalValidated validated', style: monoStyle),
          gap,
          separator,
          gap,
          Text('$passedCount passed', style: accentMonoStyle),
          gap,
          separator,
          gap,
          Text('$reviewedCount reviewed', style: monoStyle),
          gap,
          separator,
          gap,
          Text('$remainingCount remaining', style: monoStyle),
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
