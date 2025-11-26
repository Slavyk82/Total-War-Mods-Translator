import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/editor_providers.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/event_bus.dart';
import '../../../models/events/batch_events.dart';
import '../../projects/providers/projects_screen_providers.dart' show projectsWithDetailsProvider;
import 'editor_data_source.dart';
import 'translation_history_dialog.dart';
import 'prompt_preview_dialog.dart';
import 'delete_confirmation_dialog.dart';
import 'cell_renderers/context_menu_builder.dart';
import 'grid_actions_handler.dart';
import 'grid_selection_handler.dart';
import '../../../services/translation/models/translation_context.dart';
import '../../../repositories/glossary_repository.dart';
import '../../../models/domain/glossary_entry.dart';
import '../../../services/glossary/models/glossary_term_with_variants.dart';
import '../../settings/providers/settings_providers.dart';

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
  
  // Event subscriptions for auto-refresh
  StreamSubscription<BatchCompletedEvent>? _batchCompletedSubscription;
  StreamSubscription<BatchProgressEvent>? _batchProgressSubscription;

  @override
  void initState() {
    super.initState();
    
    // Create data source first (will be updated with selection handler reference)
    _dataSource = EditorDataSource(
      onCellEdit: widget.onCellEdit,
      onCellTap: (unitId) {},
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
      final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();
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
  /// Uses EventBus directly to avoid ref.listen restrictions
  void _setupBatchEventListeners() {
    // Listen to batch completed events to refresh when translation finishes
    _batchCompletedSubscription = EventBus.instance.on<BatchCompletedEvent>().listen((event) {
      // Only refresh if this event is for our current project language
      if (event.projectLanguageId == _currentProjectLanguageId) {
        _refreshTranslations();
      }
    });

    // Also listen to batch progress events for real-time updates (throttled)
    // This allows users to see translations appear as they complete
    _batchProgressSubscription = EventBus.instance.on<BatchProgressEvent>().listen((event) {
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
    // Watch filtered translation rows provider (applies sidebar filters)
    final rowsAsync = ref.watch(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );

    return rowsAsync.when(
      loading: () => const Center(
        child: CircularProgressIndicator(),
      ),
      error: (error, stack) => Center(
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
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      data: (rows) {
        _dataSource.updateDataSource(rows);

        return MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape):
                _handleEscape,
              const SingleActivator(LogicalKeyboardKey.delete):
                _handleDelete,
              const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                _handleCopy,
              const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                _handlePaste,
            },
            child: Focus(
              autofocus: true,
              child: SfDataGrid(
                source: _dataSource,
                controller: _controller,
                allowEditing: true,
                allowSorting: true,
                allowMultiColumnSorting: false,
                selectionMode: SelectionMode.multiple,
                navigationMode: GridNavigationMode.cell,
                columnWidthMode: ColumnWidthMode.fill,
                gridLinesVisibility: GridLinesVisibility.horizontal,
                headerGridLinesVisibility: GridLinesVisibility.horizontal,
                onQueryRowHeight: _calculateRowHeight,
                headerRowHeight: 48,
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
                    columnName: 'status',
                    width: 60,
                    label: Container(
                      padding: const EdgeInsets.all(8.0),
                      alignment: Alignment.center,
                      child: const Icon(
                        FluentIcons.status_24_regular,
                        size: 16,
                      ),
                    ),
                  ),
                  GridColumn(
                    columnName: 'key',
                    width: 150,
                    label: _buildColumnHeader('Key'),
                  ),
                  GridColumn(
                    columnName: 'sourceText',
                    columnWidthMode: ColumnWidthMode.fill,
                    label: _buildColumnHeader('Source Text'),
                  ),
                  GridColumn(
                    columnName: 'translatedText',
                    columnWidthMode: ColumnWidthMode.fill,
                    allowEditing: true,
                    label: _buildColumnHeader('Translated Text'),
                  ),
                  GridColumn(
                    columnName: 'tmSource',
                    width: 120,
                    label: _buildColumnHeader('TM Source'),
                  ),
                  GridColumn(
                    columnName: 'confidence',
                    width: 90,
                    label: _buildColumnHeader('Score'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Performance: Build column header as const-friendly widget
  Widget _buildColumnHeader(String text) {
    return _ColumnHeader(text: text);
  }

  void _handleCellTap(DataGridCellTapDetails details) {
    _selectionHandler.handleCellTap(details);
  }

  void _handleCellDoubleTap(DataGridCellDoubleTapDetails details) {
    if (details.rowColumnIndex.rowIndex == 0) return; // Header row

    final rowIndex = details.rowColumnIndex.rowIndex - 1;
    if (rowIndex < 0) return;

    // Let Syncfusion's native double-tap editing handle the cell edit
    // Only trigger the optional row double-tap callback for additional actions
    if (widget.onRowDoubleTap != null && rowIndex < _dataSource.translationRows.length) {
      final unitId = _dataSource.translationRows[rowIndex].id;
      widget.onRowDoubleTap!(unitId);
    }
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

    // Show context menu with grid row index for editing
    _showContextMenu(context, details.globalPosition, row, details.rowColumnIndex.rowIndex);
  }

  void _showContextMenu(BuildContext context, Offset position, TranslationRow row, int gridRowIndex) {
    ContextMenuBuilder.showContextMenu(
      context: context,
      position: position,
      row: row,
      selectionCount: _selectedRowIds.length,
      onEdit: () => _handleEdit(gridRowIndex),
      onSelectAll: _handleSelectAll,
      onClear: _handleClear,
      onViewHistory: () => _handleViewHistory(row),
      onDelete: _handleDeleteConfirmation,
      onForceRetranslate: widget.onForceRetranslate,
      onViewPrompt: () => _handleViewPrompt(row),
    );
  }

  void _handleSelectAll() {
    _selectionHandler.selectAll();
  }

  void _handleEscape() {
    _selectionHandler.clearSelection();
  }

  void _handleDelete() {
    _handleDeleteConfirmation();
  }

  /// Copy selected rows to clipboard in TSV format
  Future<void> _handleCopy() async {
    final handler = _createActionsHandler();
    await handler.handleCopy(_controller.selectedRows);
  }

  /// Paste from clipboard and update translations
  Future<void> _handlePaste() async {
    final handler = _createActionsHandler();
    await handler.handlePaste();
  }

  /// Edit the selected row inline using the grid's visual row index
  void _handleEdit(int gridRowIndex) {
    // Column 4 is translatedText (0:checkbox, 1:status, 2:key, 3:sourceText, 4:translatedText)
    final rowColumnIndex = RowColumnIndex(gridRowIndex, 4);
    _controller.beginEdit(rowColumnIndex);
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
    final translationContext = await _buildTranslationContext();
    if (!mounted || translationContext == null) return;

    await showDialog(
      context: context,
      builder: (context) => PromptPreviewDialog(
        unit: row.unit,
        context: translationContext,
      ),
    );
  }

  /// Build translation context for prompt preview
  Future<TranslationContext?> _buildTranslationContext() async {
    try {
      final projectLanguageRepo = ServiceLocator.get<ProjectLanguageRepository>();
      final glossaryRepo = ServiceLocator.get<GlossaryRepository>();

      // Get LLM provider from the toolbar's model selector dropdown
      String providerCode;
      String? modelId;

      final selectedModelId = ref.read(selectedLlmModelProvider);
      if (selectedModelId != null) {
        final modelRepo = ref.read(llmProviderModelRepositoryProvider);
        final modelResult = await modelRepo.getById(selectedModelId);
        if (modelResult.isOk) {
          final model = modelResult.unwrap();
          providerCode = model.providerCode;
          modelId = model.modelId;
        } else {
          // Fallback to settings if model not found
          final llmSettings = await ref.read(llmProviderSettingsProvider.future);
          providerCode = llmSettings[SettingsKeys.activeProvider] ?? 'openai';
        }
      } else {
        // Fallback to settings if no model selected
        final llmSettings = await ref.read(llmProviderSettingsProvider.future);
        providerCode = llmSettings[SettingsKeys.activeProvider] ?? 'openai';
      }

      // Get project language
      final projectLanguagesResult =
          await projectLanguageRepo.getByProject(widget.projectId);
      if (projectLanguagesResult.isErr) return null;

      final projectLanguages = projectLanguagesResult.unwrap();
      final projectLanguage = projectLanguages.firstWhere(
        (pl) => pl.languageId == widget.languageId,
        orElse: () => throw Exception('Project language not found'),
      );

      // Get target language
      final langRepo = ref.read(languageRepositoryProvider);
      final langResult = await langRepo.getById(widget.languageId);
      if (langResult.isErr) return null;
      final language = langResult.unwrap();

      // Load glossary entries for this project (global + project-specific)
      List<GlossaryTermWithVariants>? glossaryEntries;
      final entriesResult = await glossaryRepo.getByProjectAndLanguage(
        widget.projectId,
        widget.languageId,
      );
      if (entriesResult.isOk) {
        final entries = entriesResult.unwrap();
        // Group entries by source term for variant support
        glossaryEntries = _groupEntriesBySourceTerm(entries, language.code);
      }

      return TranslationContext(
        id: 'preview-${DateTime.now().millisecondsSinceEpoch}',
        projectId: widget.projectId,
        projectLanguageId: projectLanguage.id,
        providerId: providerCode,
        modelId: modelId,
        targetLanguage: language.code,
        glossaryEntries: glossaryEntries,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Group glossary entries by source term for variant support
  List<GlossaryTermWithVariants> _groupEntriesBySourceTerm(
    List<GlossaryEntry> entries,
    String targetLanguageCode,
  ) {
    // Filter to target language entries only
    final targetEntries = entries
        .where((e) => e.targetLanguageCode == targetLanguageCode)
        .toList();

    // Group by source term (case-insensitive)
    final grouped = <String, List<GlossaryEntry>>{};
    for (final entry in targetEntries) {
      final key = entry.sourceTerm.toLowerCase();
      grouped.putIfAbsent(key, () => []).add(entry);
    }

    // Convert to GlossaryTermWithVariants
    return grouped.entries.map((entry) {
      final first = entry.value.first;
      return GlossaryTermWithVariants(
        sourceTerm: first.sourceTerm,
        caseSensitive: first.caseSensitive,
        variants: entry.value
            .map((e) => GlossaryVariant(
                  entryId: e.id,
                  targetTerm: e.targetTerm,
                  notes: e.notes,
                ))
            .toList(),
      );
    }).toList();
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

  /// Calculate dynamic row height based on text content
  double _calculateRowHeight(RowHeightDetails details) {
    if (details.rowIndex == 0) return 48.0; // Header row
    
    final rowIndex = details.rowIndex - 1;
    if (rowIndex < 0 || rowIndex >= _dataSource.translationRows.length) {
      return 56.0; // Default height
    }
    
    final row = _dataSource.translationRows[rowIndex];
    const minHeight = 56.0;
    
    // Get the width available for text columns
    final fixedColumnsWidth = 50 + 60 + 150 + 120 + 90 + 60; // = 530
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth > fixedColumnsWidth 
        ? screenWidth - fixedColumnsWidth 
        : 400.0; // Fallback width
    final columnWidth = (availableWidth / 2).clamp(200.0, double.infinity);
    
    // Calculate height for both text columns
    final sourceHeight = _calculateTextHeight(row.sourceText, columnWidth);
    final translatedHeight = _calculateTextHeight(row.translatedText ?? '', columnWidth);
    
    // Use the maximum height needed, add generous padding
    final maxContentHeight = sourceHeight > translatedHeight ? sourceHeight : translatedHeight;
    final totalHeight = maxContentHeight + 32.0; // Generous padding (16px top + 16px bottom)
    
    return totalHeight > minHeight ? totalHeight : minHeight;
  }

  /// Calculate the actual height needed for text using TextPainter
  double _calculateTextHeight(String text, double maxWidth) {
    if (text.isEmpty) return 20.0;
    
    final textStyle = const TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.normal,
    );
    
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    
    // Layout with available width minus padding (16px total)
    textPainter.layout(maxWidth: maxWidth - 16);
    
    // Add 20% extra height as safety margin
    return textPainter.height * 1.2;
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

/// Performance-optimized column header widget with const constructor
class _ColumnHeader extends StatelessWidget {
  final String text;

  const _ColumnHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
