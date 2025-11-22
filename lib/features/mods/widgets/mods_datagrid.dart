import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/project.dart';
import 'mods_data_source.dart';

/// Syncfusion DataGrid for displaying mods with sorting and filtering
class ModsDataGrid extends StatefulWidget {
  final List<Project> projects;
  final Function(String projectId) onRowTap;
  final bool isLoading;

  const ModsDataGrid({
    super.key,
    required this.projects,
    required this.onRowTap,
    this.isLoading = false,
  });

  @override
  State<ModsDataGrid> createState() => _ModsDataGridState();
}

class _ModsDataGridState extends State<ModsDataGrid> {
  late ModsDataSource _dataSource;
  final DataGridController _dataGridController = DataGridController();

  @override
  void initState() {
    super.initState();
    _dataSource = ModsDataSource(
      projects: widget.projects,
      onRowTap: widget.onRowTap,
    );
  }

  @override
  void didUpdateWidget(ModsDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.projects != oldWidget.projects) {
      _dataSource.updateProjects(widget.projects);
    }
  }

  @override
  void dispose() {
    _dataGridController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (widget.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Loading mods...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.projects.isEmpty) {
      return _buildEmptyState(theme);
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SfDataGrid(
          source: _dataSource,
          controller: _dataGridController,
          columnWidthMode: ColumnWidthMode.fill,
          gridLinesVisibility: GridLinesVisibility.horizontal,
          headerGridLinesVisibility: GridLinesVisibility.horizontal,
          allowSorting: true,
          allowMultiColumnSorting: false,
          selectionMode: SelectionMode.single,
          navigationMode: GridNavigationMode.row,
          onCellTap: (details) {
            if (details.rowColumnIndex.rowIndex > 0) {
              final rowIndex = details.rowColumnIndex.rowIndex - 1;
              if (rowIndex < widget.projects.length) {
                widget.onRowTap(widget.projects[rowIndex].id);
              }
            }
          },
          headerRowHeight: 56,
          rowHeight: 64,
          columns: [
            GridColumn(
              columnName: 'image',
              width: 64,
              label: _buildColumnHeader(
                context,
                '',
                FluentIcons.image_24_regular,
              ),
            ),
            GridColumn(
              columnName: 'workshop_id',
              width: 140,
              label: _buildColumnHeader(
                context,
                'Workshop ID',
                FluentIcons.number_symbol_24_regular,
              ),
            ),
            GridColumn(
              columnName: 'name',
              label: _buildColumnHeader(
                context,
                'Mod Name',
                FluentIcons.cube_24_regular,
              ),
            ),
            GridColumn(
              columnName: 'version',
              width: 120,
              label: _buildColumnHeader(
                context,
                'Version',
                FluentIcons.code_24_regular,
              ),
            ),
            GridColumn(
              columnName: 'status',
              width: 140,
              label: _buildColumnHeader(
                context,
                'Status',
                FluentIcons.info_24_regular,
              ),
            ),
            GridColumn(
              columnName: 'updated',
              width: 160,
              label: _buildColumnHeader(
                context,
                'Last Updated',
                FluentIcons.clock_24_regular,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnHeader(
    BuildContext context,
    String title,
    IconData icon,
  ) {
    final theme = Theme.of(context);

    // For columns with no title (like image column), show only icon centered
    if (title.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHigh,
        ),
        child: Icon(
          icon,
          size: 16,
          color: theme.colorScheme.primary,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.cube_24_regular,
            size: 64,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No mods found',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add your first Total War mod to get started',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }
}
