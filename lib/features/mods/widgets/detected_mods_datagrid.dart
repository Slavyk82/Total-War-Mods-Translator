import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/widgets/scan_terminal_widget.dart';
import 'detected_mods_data_source.dart';

/// Syncfusion DataGrid for displaying detected mods with sorting and filtering
class DetectedModsDataGrid extends StatefulWidget {
  final List<DetectedMod> mods;
  final Function(String workshopId) onRowTap;
  final Function(String workshopId, bool hide)? onToggleHidden;
  final Function(String packFilePath)? onForceRedownload;
  final bool isLoading;
  final bool isScanning;
  final bool showingHidden;
  final Stream<ScanLogMessage>? scanLogStream;

  const DetectedModsDataGrid({
    super.key,
    required this.mods,
    required this.onRowTap,
    this.onToggleHidden,
    this.onForceRedownload,
    this.isLoading = false,
    this.isScanning = false,
    this.showingHidden = false,
    this.scanLogStream,
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
      onToggleHidden: widget.onToggleHidden,
      onForceRedownload: widget.onForceRedownload,
      showingHidden: widget.showingHidden,
    );
  }

  @override
  void didUpdateWidget(DetectedModsDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recreate data source if showingHidden changed or mods changed
    if (widget.showingHidden != oldWidget.showingHidden ||
        widget.onToggleHidden != oldWidget.onToggleHidden ||
        widget.onForceRedownload != oldWidget.onForceRedownload) {
      _dataSource = DetectedModsDataSource(
        mods: widget.mods,
        onRowTap: widget.onRowTap,
        onToggleHidden: widget.onToggleHidden,
        onForceRedownload: widget.onForceRedownload,
        showingHidden: widget.showingHidden,
      );
    } else if (widget.mods != oldWidget.mods) {
      _dataSource.updateMods(widget.mods);
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

    // Initial loading state - show only terminal
    if (widget.isLoading) {
      if (widget.scanLogStream != null) {
        return ScanTerminalWidget(
          logStream: widget.scanLogStream!,
          title: 'Scanning Workshop...',
        );
      }
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
      // If scanning with no data yet, show terminal
      if (widget.isScanning && widget.scanLogStream != null) {
        return ScanTerminalWidget(
          logStream: widget.scanLogStream!,
          title: 'Scanning Workshop...',
        );
      }
      return _buildEmptyState(theme);
    }

    // Has data - show grid, with terminal overlay if scanning
    final gridWidget = _buildDataGrid(theme);

    if (widget.isScanning && widget.scanLogStream != null) {
      return Stack(
        children: [
          // Grid in background (slightly dimmed)
          Opacity(
            opacity: 0.4,
            child: gridWidget,
          ),
          // Terminal overlay
          ScanTerminalWidget(
            logStream: widget.scanLogStream!,
            title: 'Refreshing...',
          ),
        ],
      );
    }

    return gridWidget;
  }

  Widget _buildDataGrid(ThemeData theme) {
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
                // Don't trigger row tap when clicking on changes or hide columns
                final columnIndex = details.rowColumnIndex.columnIndex;
                if (columnIndex == 6 || columnIndex == 7) {
                  // Changes column (6) - handled by clickable badge
                  // Hide column (7) - handled by checkbox widget
                  return;
                }
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
            GridColumn(
              columnName: 'hide',
              width: 60,
              allowFiltering: false,
              allowSorting: false,
              label: Container(
                padding: const EdgeInsets.all(8),
                alignment: Alignment.center,
                child: Tooltip(
                  message: widget.showingHidden
                      ? 'Uncheck to show mods'
                      : 'Check to hide mods',
                  child: Icon(
                    widget.showingHidden
                        ? FluentIcons.eye_24_regular
                        : FluentIcons.eye_off_24_regular,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
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
                ? 'Use the checkbox to hide mods from the list'
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
