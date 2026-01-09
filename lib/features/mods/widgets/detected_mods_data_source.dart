import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:intl/intl.dart' show NumberFormat;

import 'package:twmt/features/mods/models/mods_cell_data.dart';
import 'package:twmt/features/mods/widgets/mods_datagrid_cells/datagrid_cell.dart'
    show TextDataGridCell;
import 'package:twmt/features/mods/widgets/mods_datagrid_cells/mod_image_cell.dart';
import 'package:twmt/features/mods/widgets/mods_datagrid_cells/last_updated_cell.dart';
import 'package:twmt/features/mods/widgets/mods_datagrid_cells/imported_badge.dart';
import 'package:twmt/features/mods/widgets/mods_datagrid_cells/changes_cell.dart';
import 'package:twmt/features/mods/widgets/mods_datagrid_cells/hide_checkbox.dart';

/// Data source for Syncfusion DataGrid displaying detected mods.
///
/// This class handles the conversion of [DetectedMod] objects into
/// [DataGridRow] entries and builds the visual representation of each
/// row using specialized cell widgets.
class DetectedModsDataSource extends DataGridSource {
  DetectedModsDataSource({
    required List<DetectedMod> mods,
    required this.onRowTap,
    this.onToggleHidden,
    this.onForceRedownload,
    this.showingHidden = false,
  }) {
    _mods = mods;
    _buildDataGridRows();
  }

  List<DetectedMod> _mods = [];
  List<DataGridRow> _dataGridRows = [];
  final Function(String workshopId) onRowTap;
  final Function(String workshopId, bool hide)? onToggleHidden;
  final Function(String packFilePath)? onForceRedownload;
  final bool showingHidden;

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  int compare(DataGridRow? a, DataGridRow? b, SortColumnDetails sortColumn) {
    if (a == null || b == null) return 0;

    final aCell = a.getCells().firstWhere(
          (cell) => cell.columnName == sortColumn.name,
        );
    final bCell = b.getCells().firstWhere(
          (cell) => cell.columnName == sortColumn.name,
        );

    final aValue = aCell.value;
    final bValue = bCell.value;

    if (aValue == null && bValue == null) return 0;
    if (aValue == null) return sortColumn.sortDirection == DataGridSortDirection.ascending ? 1 : -1;
    if (bValue == null) return sortColumn.sortDirection == DataGridSortDirection.ascending ? -1 : 1;

    int comparison;
    if (aValue is Comparable && bValue is Comparable) {
      comparison = aValue.compareTo(bValue);
    } else {
      comparison = aValue.toString().compareTo(bValue.toString());
    }

    return sortColumn.sortDirection == DataGridSortDirection.ascending
        ? comparison
        : -comparison;
  }

  /// Update the data source with new mods.
  void updateMods(List<DetectedMod> mods) {
    if (_mods == mods) return;
    _mods = mods;
    _buildDataGridRows();
    notifyListeners();
  }

  /// Build data grid rows from mods.
  void _buildDataGridRows() {
    _dataGridRows = _mods.map<DataGridRow>((mod) {
      return DataGridRow(
        cells: [
          DataGridCell<String?>(
            columnName: 'image',
            value: mod.imageUrl,
          ),
          DataGridCell<String>(
            columnName: 'workshop_id',
            value: mod.workshopId,
          ),
          DataGridCell<String>(
            columnName: 'name',
            value: mod.name,
          ),
          DataGridCell<int>(
            columnName: 'subscribers',
            value: mod.metadata?.modSubscribers ?? 0,
          ),
          DataGridCell<LastUpdatedData>(
            columnName: 'last_updated',
            value: LastUpdatedData(
              timeUpdated: mod.timeUpdated,
              localFileLastModified: mod.localFileLastModified,
              updateStatus: mod.updateStatus,
            ),
          ),
          DataGridCell<ImportedData>(
            columnName: 'imported',
            value: ImportedData(isImported: mod.isAlreadyImported),
          ),
          DataGridCell<ChangesData>(
            columnName: 'changes',
            value: ChangesData(
              analysis: mod.updateAnalysis,
              updateStatus: mod.updateStatus,
              packFilePath: mod.packFilePath,
            ),
          ),
          DataGridCell<HideData>(
            columnName: 'hide',
            value: HideData(
              workshopId: mod.workshopId,
              isHidden: mod.isHidden,
            ),
          ),
        ],
      );
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final imageUrl = cells[0].value as String?;
    final workshopId = cells[1].value.toString();
    final modName = cells[2].value.toString();
    final subscribers = cells[3].value as int;
    final lastUpdatedData = cells[4].value as LastUpdatedData;
    final importedData = cells[5].value as ImportedData;
    final changesData = cells[6].value as ChangesData;
    final hideData = cells[7].value as HideData;

    return DataGridRowAdapter(
      cells: [
        // Mod Image
        RepaintBoundary(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            child: ModImageCell(imageUrl: imageUrl),
          ),
        ),
        // Workshop ID
        RepaintBoundary(
          child: TextDataGridCell(
            text: workshopId,
            fontFamily: 'monospace',
          ),
        ),
        // Mod Name
        RepaintBoundary(
          child: TextDataGridCell(
            text: modName,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Subscribers
        RepaintBoundary(
          child: TextDataGridCell(
            text: subscribers > 0
                ? NumberFormat('#,###', 'en_US')
                    .format(subscribers)
                    .replaceAll(',', ' ')
                : '-',
          ),
        ),
        // Last Updated
        RepaintBoundary(
          child: LastUpdatedCell(data: lastUpdatedData),
        ),
        // Imported Status
        RepaintBoundary(
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(8),
            child: ImportedBadge(isImported: importedData.isImported),
          ),
        ),
        // Changes Analysis
        RepaintBoundary(
          child: ChangesCell(
            data: changesData,
            isImported: importedData.isImported,
            onForceRedownload: onForceRedownload,
          ),
        ),
        // Hide checkbox
        RepaintBoundary(
          child: HideCheckbox(
            data: hideData,
            showingHidden: showingHidden,
            onToggle: onToggleHidden,
          ),
        ),
      ],
    );
  }
}
