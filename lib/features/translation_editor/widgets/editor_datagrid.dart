import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_core/theme.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/token_data_grid_theme.dart';
import '../providers/editor_providers.dart';
import '../../../providers/shared/repository_providers.dart' as shared_repo;
import '../../../providers/shared/service_providers.dart';
import '../../../models/events/batch_events.dart';
import '../../projects/providers/projects_screen_providers.dart' show projectsWithDetailsProvider;
import 'editor_data_source.dart';
import 'translation_history_dialog.dart';
import 'prompt_preview_dialog.dart';
import 'delete_confirmation_dialog.dart';
import 'cell_renderers/context_menu_builder.dart';
import 'grid_actions_handler.dart';
import 'grid_selection_handler.dart';
import 'translation_context_builder.dart';

/// Main DataGrid widget for translation editor
///
/// Handles display, inline editing, multi-select, sorting, and context menus
class EditorDataGrid extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final Function(String unitId, String newText) onCellEdit;
  final Function(String unitId)? onRowDoubleTap;
  final Future<void> Function()? onForceRetranslate;

  const EditorDataGrid({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onCellEdit,
    this.onRowDoubleTap,
    this.onForceRetranslate,
  });

  @override
  ConsumerState<EditorDataGrid> createState() => _EditorDataGridState();
}

class _EditorDataGridState extends ConsumerState<EditorDataGrid> {
  late EditorDataSource _dataSource;
  final DataGridController _controller = DataGridController();
  late GridSelectionHandler _selectionHandler;
  Set<String> _selectedRowIds = {};
  String? _currentProjectLanguageId;

  // Scroll controller to preserve scroll position on data refresh
  final ScrollController _verticalScrollController = ScrollController();

  // Focus node that captures arrow-key presses so the user can walk the
  // selection up/down with the keyboard. The inspector's target TextField
  // owns its own focus, so caret navigation inside that field is unaffected.
  final FocusNode _gridFocusNode = FocusNode(debugLabel: 'EditorDataGrid');

  // Cache previous rows to maintain display during refresh
  List<TranslationRow>? _cachedRows;

  // Event subscriptions for auto-refresh
  StreamSubscription<BatchCompletedEvent>? _batchCompletedSubscription;
  StreamSubscription<BatchProgressEvent>? _batchProgressSubscription;

  @override
  void initState() {
    super.initState();

    // Create data source first (will be updated with selection handler reference)
    _dataSource = EditorDataSource(
      onCellEdit: widget.onCellEdit,
      onCheckboxTap: (unitId) {}, // Placeholder, will be replaced
      isRowSelected: (unitId) => _selectedRowIds.contains(unitId),
    );

    // Create selection handler with the data source
    _selectionHandler = GridSelectionHandler(
      dataSource: _dataSource,
      controller: _controller,
      ref: ref,
      onSelectionChanged: (selectedIds, _) {
        setState(() {
          _selectedRowIds = selectedIds;
        });
      },
    );

    // Now update the data source callbacks to use the selection handler
    _dataSource.onCheckboxTap = _selectionHandler.handleCheckboxTap;
    _dataSource.isRowSelected = _selectionHandler.isRowSelected;

    // Get the project language ID for this editor to filter batch events
    _loadProjectLanguageId();

    // Listen to batch events and refresh data when translations are completed
    _setupBatchEventListeners();
  }

  /// Load the project language ID for filtering events
  Future<void> _loadProjectLanguageId() async {
    try {
      final projectLanguageRepo = ref.read(shared_repo.projectLanguageRepositoryProvider);
      final projectLanguagesResult = await projectLanguageRepo.getByProject(widget.projectId);

      if (projectLanguagesResult.isOk) {
        final projectLanguages = projectLanguagesResult.unwrap();
        final projectLanguage = projectLanguages.firstWhere(
          (pl) => pl.languageId == widget.languageId,
          orElse: () => throw Exception('Project language not found'),
        );
        
        if (mounted) {
          setState(() {
            _currentProjectLanguageId = projectLanguage.id;
          });
        }
      }
    } catch (e) {
      // Error loading project language ID, event filtering won't work but non-critical
    }
  }

  /// Setup listeners for batch events to auto-refresh data
  /// Uses EventBus via provider to avoid ref.listen restrictions
  void _setupBatchEventListeners() {
    final eventBus = ref.read(eventBusProvider);

    // Listen to batch completed events to refresh when translation finishes
    _batchCompletedSubscription = eventBus.on<BatchCompletedEvent>().listen((event) {
      // Only refresh if this event is for our current project language
      if (event.projectLanguageId == _currentProjectLanguageId) {
        _refreshTranslations();
      }
    });

    // Also listen to batch progress events for real-time updates (throttled)
    // This allows users to see translations appear as they complete
    _batchProgressSubscription = eventBus.on<BatchProgressEvent>().listen((event) {
      // Refresh every 10 completed units to show incremental progress
      // without overwhelming the UI with constant refreshes
      if (event.completedUnits % 10 == 0 && _currentProjectLanguageId != null) {
        _refreshTranslations();
      }
    });
  }

  /// Refresh translation data by invalidating the provider
  void _refreshTranslations() {
    if (mounted) {
      ref.invalidate(translationRowsProvider(widget.projectId, widget.languageId));
      // Also refresh project stats displayed on project cards
      ref.invalidate(projectsWithDetailsProvider);
    }
  }

  @override
  void dispose() {
    _batchCompletedSubscription?.cancel();
    _batchProgressSubscription?.cancel();
    _verticalScrollController.dispose();
    _gridFocusNode.dispose();
    _dataSource.dispose();
    _controller.dispose();
    super.dispose();
  }

  GridActionsHandler _createActionsHandler() {
    return GridActionsHandler(
      context: context,
      ref: ref,
      dataSource: _dataSource,
      selectedRowIds: _selectedRowIds,
      projectId: widget.projectId,
      languageId: widget.languageId,
      onCellEdit: widget.onCellEdit,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Keep the grid's checkbox column in lockstep with external mutations of
    // `editorSelectionProvider` (e.g. Ctrl+A fired from the screen-scope
    // Shortcuts map). `syncFromProvider` is a no-op when the provider and the
    // grid already agree, so taps routed through `GridSelectionHandler` —
    // which write to the provider themselves — don't cause a feedback loop.
    ref.listen(editorSelectionProvider, (prev, next) {
      _selectionHandler.syncFromProvider(next.selectedUnitIds);
    });

    // Watch filtered translation rows provider (applies sidebar filters)
    final rowsAsync = ref.watch(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );

    // Cache new data when available, keep using cached data during refresh
    final newRows = rowsAsync.asData?.value;
    if (newRows != null) {
      _cachedRows = newRows;
    }
    final rows = _cachedRows;
    final isLoading = rowsAsync.isLoading;
    final hasError = rowsAsync.hasError;

    // Show loading only on initial load (no cached data)
    if (rows == null && isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    // Show error only if no cached data available
    if (rows == null && hasError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              FluentIcons.error_circle_24_regular,
              size: 48,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading translations',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              rowsAsync.error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    // Update data source with cached data
    if (rows != null) {
      _dataSource.updateDataSource(rows);
    }

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
                verticalScrollController: _verticalScrollController,
                allowEditing: false,
                // Sort arrows clutter the tokenised header (mono caps); the
                // mockup intentionally omits them in favour of filter chips.
                allowSorting: false,
                allowMultiColumnSorting: false,
                selectionMode: SelectionMode.none,
                navigationMode: GridNavigationMode.row,
                columnWidthMode: ColumnWidthMode.fill,
                gridLinesVisibility: GridLinesVisibility.horizontal,
                headerGridLinesVisibility: GridLinesVisibility.horizontal,
                // Fixed row height: using a static height (instead of
                // `onQueryRowHeight`) avoids Syncfusion re-measuring rows on
                // every `notifyListeners()`, which otherwise shifts the
                // scroll offset when the user clicks a tall row. Long text
                // is truncated here and shown in full by the right-hand
                // inspector.
                rowHeight: 44,
                headerRowHeight: 30,
                onCellTap: _handleCellTap,
                onCellSecondaryTap: _handleCellSecondaryTap,
                columns: [
                  GridColumn(
                    columnName: 'checkbox',
                    width: 50,
                    allowSorting: false,
                    label: Container(
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
                    ),
                  ),
                  GridColumn(
                    columnName: 'key',
                    width: 150,
                    allowSorting: false,
                    label: _buildColumnHeader('KEY'),
                  ),
                  GridColumn(
                    columnName: 'sourceText',
                    columnWidthMode: ColumnWidthMode.fill,
                    allowSorting: false,
                    label: _buildColumnHeader('SOURCE'),
                  ),
                  GridColumn(
                    columnName: 'translatedText',
                    columnWidthMode: ColumnWidthMode.fill,
                    allowSorting: false,
                    label: _buildColumnHeader('TARGET'),
                  ),
                ],
            ),
          ),
          ),
        );
  }

  // Performance: Build column header as const-friendly widget
  Widget _buildColumnHeader(String text) {
    return _ColumnHeader(text: text);
  }

  void _handleCellTap(DataGridCellTapDetails details) {
    _selectionHandler.handleCellTap(details);
    // Pull focus onto the grid so subsequent arrow-key presses drive row
    // navigation (instead of leaving focus on whatever last held it, e.g.
    // the inspector's target text field).
    _gridFocusNode.requestFocus();
  }

  /// Keyboard navigation: Up/Down arrows move the single selection one row
  /// at a time, replacing the current selection. The inspector's selection
  /// listener picks this up and rebinds the target field automatically,
  /// flushing any dirty text for the previous unit before switching.
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

    final rows = _dataSource.translationRows;
    if (rows.isEmpty) return KeyEventResult.ignored;

    int? currentIndex = _selectionHandler.lastClickedIndex;
    if (currentIndex == null && _selectedRowIds.length == 1) {
      final id = _selectedRowIds.first;
      final idx = rows.indexWhere((r) => r.id == id);
      if (idx >= 0) currentIndex = idx;
    }
    if (currentIndex == null) return KeyEventResult.ignored;

    final newIndex = (currentIndex + delta).clamp(0, rows.length - 1);
    if (newIndex == currentIndex) return KeyEventResult.handled;

    _selectionHandler.selectSingleRow(rows[newIndex].id, newIndex);
    // Only scroll when the new row would otherwise fall outside the viewport.
    // The default `DataGridScrollPosition.start` mode snaps every step to the
    // top of the viewport, which both looks jumpy and forces Syncfusion to
    // rebuild the visible row window — a rebuild that tears down our Focus
    // subtree and drops the keyboard focus mid-navigation. `makeVisible`
    // leaves the scroll alone while the row is in view and only nudges it
    // when needed, so arrow-key focus survives the walk.
    _controller.scrollToRow(
      newIndex.toDouble(),
      position: DataGridScrollPosition.makeVisible,
    );
    return KeyEventResult.handled;
  }

  void _handleCellSecondaryTap(DataGridCellTapDetails details) {
    if (details.rowColumnIndex.rowIndex == 0) return; // Header row

    final rowIndex = details.rowColumnIndex.rowIndex - 1;
    if (rowIndex < 0 || rowIndex >= _dataSource.translationRows.length) return;

    final row = _dataSource.translationRows[rowIndex];

    // If the right-clicked row is not in the current selection, select only it
    if (!_selectedRowIds.contains(row.id)) {
      _selectionHandler.selectSingleRow(row.id, rowIndex);
    }

    _gridFocusNode.requestFocus();

    // Show context menu with grid row index for editing
    _showContextMenu(context, details.globalPosition, row, details.rowColumnIndex.rowIndex);
  }

  void _showContextMenu(BuildContext context, Offset position, TranslationRow row, int gridRowIndex) {
    ContextMenuBuilder.showContextMenu(
      context: context,
      ref: ref,
      position: position,
      row: row,
      selectionCount: _selectedRowIds.length,
      onSelectAll: _handleSelectAll,
      onClear: _handleClear,
      onViewHistory: () => _handleViewHistory(row),
      onDelete: _handleDeleteConfirmation,
      onForceRetranslate: widget.onForceRetranslate,
      onViewPrompt: () => _handleViewPrompt(row),
      onMarkAsTranslated: _handleValidate,
    );
  }

  void _handleSelectAll() {
    _selectionHandler.selectAll();
  }

  /// Mark selected translations as reviewed
  Future<void> _handleValidate() async {
    final handler = _createActionsHandler();
    await handler.handleValidate();
  }

  /// Clear translation text for selected rows
  Future<void> _handleClear() async {
    final handler = _createActionsHandler();
    await handler.handleClear();
  }

  /// Show history dialog for a translation
  Future<void> _handleViewHistory(TranslationRow row) async {
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => TranslationHistoryDialog(
        versionId: row.version.id,
        unitKey: row.key,
      ),
    );
  }

  /// Show prompt preview dialog for a translation unit
  Future<void> _handleViewPrompt(TranslationRow row) async {
    if (!mounted) return;

    // Build a translation context for the preview
    final translationContext = await TranslationContextBuilder.build(
      ref,
      widget.projectId,
      widget.languageId,
    );
    if (!mounted || translationContext == null) return;

    await showDialog(
      context: context,
      builder: (context) => PromptPreviewDialog(
        unit: row.unit,
        context: translationContext,
      ),
    );
  }

  /// Show delete confirmation dialog
  Future<void> _handleDeleteConfirmation() async {
    if (_selectedRowIds.isEmpty || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DeleteConfirmationDialog(
        count: _selectedRowIds.length,
      ),
    );

    if (confirmed == true) {
      await _performDelete();
    }
  }

  /// Perform the actual deletion
  Future<void> _performDelete() async {
    final handler = _createActionsHandler();
    await handler.performDelete(() {
      _selectionHandler.clearSelection();
    });
  }

  /// Get the state of the "select all" checkbox in the header
  /// Returns null (indeterminate) if some rows are selected
  /// Returns true if all rows are selected
  /// Returns false if no rows are selected
  bool? _getSelectAllCheckboxState() {
    if (_selectedRowIds.isEmpty) return false;
    
    final totalRows = _dataSource.translationRows.length;
    if (_selectedRowIds.length == totalRows) return true;
    
    return null; // Indeterminate state
  }

  /// Handle click on the "select all" checkbox in the header
  /// If all rows are selected, deselect all
  /// Otherwise, select all rows
  void _handleSelectAllCheckbox() {
    if (_getSelectAllCheckboxState() == true) {
      // All selected, so deselect all
      _selectionHandler.clearSelection();
    } else {
      // Some or none selected, so select all
      _selectionHandler.selectAll();
    }
  }
}

/// Tokenised column header used by the editor data grid.
///
/// Renders the column label in the theme's monospace face, all-caps, with the
/// faint text colour and wide letter-spacing called out in the mockup. The
/// caller is expected to pass an already-uppercased [text] (matching the
/// labels in the mockup) so the constructor can stay `const`-friendly.
class _ColumnHeader extends StatelessWidget {
  final String text;

  const _ColumnHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: tokens.fontMono.copyWith(
          fontSize: 10,
          color: tokens.textFaint,
          letterSpacing: 1.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
