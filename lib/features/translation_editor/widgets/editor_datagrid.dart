import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/editor_providers.dart';
import 'editor_data_source.dart';
import 'translation_history_dialog.dart';
import 'delete_confirmation_dialog.dart';
import 'cell_renderers/context_menu_builder.dart';
import 'grid_actions_handler.dart';
import 'grid_selection_handler.dart';

/// Main DataGrid widget for translation editor
///
/// Handles display, inline editing, multi-select, sorting, and context menus
class EditorDataGrid extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final Function(String unitId, String newText) onCellEdit;
  final Function(String unitId)? onRowDoubleTap;

  const EditorDataGrid({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onCellEdit,
    this.onRowDoubleTap,
  });

  @override
  ConsumerState<EditorDataGrid> createState() => _EditorDataGridState();
}

class _EditorDataGridState extends ConsumerState<EditorDataGrid> {
  late EditorDataSource _dataSource;
  final DataGridController _controller = DataGridController();
  late GridSelectionHandler _selectionHandler;
  Set<String> _selectedRowIds = {};

  @override
  void initState() {
    super.initState();
    _dataSource = EditorDataSource(
      onCellEdit: widget.onCellEdit,
      onCellTap: (unitId) {
        // Handle row tap
      },
      onCheckboxTap: (unitId) {},
      isRowSelected: (unitId) => _selectedRowIds.contains(unitId),
    );
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
    // Update data source with selection handler's checkbox callback
    _dataSource = EditorDataSource(
      onCellEdit: widget.onCellEdit,
      onCellTap: (unitId) {},
      onCheckboxTap: _selectionHandler.handleCheckboxTap,
      isRowSelected: (unitId) => _selectionHandler.isRowSelected(unitId),
    );
  }

  @override
  void dispose() {
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
    // Watch translation rows provider
    final rowsAsync = ref.watch(
      translationRowsProvider(widget.projectId, widget.languageId),
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
              const SingleActivator(LogicalKeyboardKey.keyA, control: true):
                _handleSelectAll,
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
                rowHeight: 56,
                headerRowHeight: 48,
                onCellTap: _handleCellTap,
                onCellDoubleTap: _handleCellDoubleTap,
                onCellSecondaryTap: _handleCellSecondaryTap,
                columns: [
                  GridColumn(
                    columnName: 'checkbox',
                    width: 50,
                    label: Container(
                      padding: const EdgeInsets.all(8.0),
                      alignment: Alignment.center,
                      child: Checkbox(
                        value: false,
                        tristate: true,
                        onChanged: (value) {
                          // TODO: Select all checkbox
                        },
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
                  GridColumn(
                    columnName: 'actions',
                    width: 60,
                    label: Container(
                      padding: const EdgeInsets.all(8.0),
                      alignment: Alignment.center,
                      child: const Icon(
                        FluentIcons.more_horizontal_24_regular,
                        size: 16,
                      ),
                    ),
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

    // Enable editing for translated text column
    final columnIndex = details.rowColumnIndex.columnIndex;
    if (columnIndex == 3) { // translatedText column
      _controller.beginEdit(details.rowColumnIndex);
    }

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

    // Show context menu
    _showContextMenu(context, details.globalPosition, row);
  }

  void _showContextMenu(BuildContext context, Offset position, TranslationRow row) {
    ContextMenuBuilder.showContextMenu(
      context: context,
      position: position,
      row: row,
      selectionCount: _selectedRowIds.length,
      onEdit: () => _handleEdit(row),
      onSelectAll: _handleSelectAll,
      onCopy: _handleCopy,
      onPaste: _handlePaste,
      onValidate: _handleValidate,
      onClear: _handleClear,
      onViewHistory: () => _handleViewHistory(row),
      onDelete: _handleDeleteConfirmation,
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

  /// Edit the selected row inline
  void _handleEdit(TranslationRow row) {
    final rowIndex = _dataSource.translationRows.indexOf(row);
    if (rowIndex == -1) return;

    final rowColumnIndex = RowColumnIndex(rowIndex + 1, 3);
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
