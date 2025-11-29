import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'detected_mods_data_source.dart';

/// Syncfusion DataGrid for displaying detected mods with sorting and filtering
class DetectedModsDataGrid extends StatefulWidget {
  final List<DetectedMod> mods;
  final Function(String workshopId) onRowTap;
  final Function(String workshopId, bool hide)? onToggleHidden;
  final bool isLoading;
  final bool showingHidden;

  const DetectedModsDataGrid({
    super.key,
    required this.mods,
    required this.onRowTap,
    this.onToggleHidden,
    this.isLoading = false,
    this.showingHidden = false,
  });

  @override
  State<DetectedModsDataGrid> createState() => _DetectedModsDataGridState();
}

class _DetectedModsDataGridState extends State<DetectedModsDataGrid> {
  late DetectedModsDataSource _dataSource;
  final DataGridController _dataGridController = DataGridController();

  @override
  void initState() {
    super.initState();
    _dataSource = DetectedModsDataSource(
      mods: widget.mods,
      onRowTap: widget.onRowTap,
    );
  }

  @override
  void didUpdateWidget(DetectedModsDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mods != oldWidget.mods) {
      _dataSource.updateMods(widget.mods);
    }
  }

  @override
  void dispose() {
    _dataGridController.dispose();
    super.dispose();
  }

  void _showContextMenu(BuildContext context, Offset position, DetectedMod mod) {
    final theme = Theme.of(context);
    final isHidden = mod.isHidden;
    
    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'toggle_hidden',
          child: Row(
            children: [
              Icon(
                isHidden
                    ? FluentIcons.eye_24_regular
                    : FluentIcons.eye_off_24_regular,
                size: 20,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 12),
              Text(isHidden ? 'Unhide mod' : 'Hide mod'),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'toggle_hidden' && widget.onToggleHidden != null) {
        widget.onToggleHidden!(mod.workshopId, !isHidden);
      }
    });
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
              'Scanning Workshop folder...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.mods.isEmpty) {
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
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            // Find which row was clicked based on Y position
            // Account for header row (56px) and row height (64px)
            final localY = details.localPosition.dy;
            if (localY > 56) { // Skip header
              final rowIndex = ((localY - 56) / 64).floor();
              if (rowIndex >= 0 && rowIndex < widget.mods.length) {
                _showContextMenu(context, details.globalPosition, widget.mods[rowIndex]);
              }
            }
          },
          child: SfDataGrid(
            source: _dataSource,
            controller: _dataGridController,
            gridLinesVisibility: GridLinesVisibility.horizontal,
            headerGridLinesVisibility: GridLinesVisibility.horizontal,
            allowSorting: true,
            allowMultiColumnSorting: false,
            selectionMode: SelectionMode.single,
            navigationMode: GridNavigationMode.row,
            onCellTap: (details) {
              if (details.rowColumnIndex.rowIndex > 0) {
                final rowIndex = details.rowColumnIndex.rowIndex - 1;
                if (rowIndex < widget.mods.length) {
                  widget.onRowTap(widget.mods[rowIndex].workshopId);
                }
              }
            },
            headerRowHeight: 56,
            rowHeight: 64,
          columns: <GridColumn>[
            GridColumn(
              columnName: 'image',
              width: 64,
              allowFiltering: false,
              allowSorting: false,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                ),
                child: const SizedBox.shrink(),
              ),
            ),
            GridColumn(
              columnName: 'workshop_id',
              width: 140,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.number_symbol_24_regular,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'ID',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GridColumn(
              columnName: 'name',
              columnWidthMode: ColumnWidthMode.fill,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.cube_24_regular,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Mod Name',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GridColumn(
              columnName: 'subscribers',
              width: 120,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.people_24_regular,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Subs',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GridColumn(
              columnName: 'last_updated',
              width: 170,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.calendar_24_regular,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Last Updated',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GridColumn(
              columnName: 'imported',
              width: 140,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.tag_24_regular,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Status',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            GridColumn(
              columnName: 'changes',
              width: 180,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.arrow_sync_24_regular,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Changes',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final isShowingHidden = widget.showingHidden;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isShowingHidden 
                ? FluentIcons.eye_off_24_regular 
                : FluentIcons.cube_24_regular,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            isShowingHidden ? 'No hidden mods' : 'No mods found',
            style: theme.textTheme.headlineMedium?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isShowingHidden
                ? 'Right-click on a mod to hide it from the list'
                : 'Subscribe to mods on Steam Workshop or download them manually',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

