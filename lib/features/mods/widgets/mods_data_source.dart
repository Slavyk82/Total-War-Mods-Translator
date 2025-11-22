import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:cached_network_image/cached_network_image.dart';

/// Data source for Syncfusion DataGrid displaying mod projects
class ModsDataSource extends DataGridSource {
  ModsDataSource({
    required List<Project> projects,
    required this.onRowTap,
  }) {
    _projects = projects;
    _buildDataGridRows();
  }

  List<Project> _projects = [];
  List<DataGridRow> _dataGridRows = [];
  final Function(String projectId) onRowTap;

  // Performance: Cache for DataGridRow objects to avoid rebuilding unchanged rows
  final Map<int, DataGridRowAdapter> _rowAdapterCache = {};

  @override
  List<DataGridRow> get rows => _dataGridRows;

  /// Update the data source with new projects
  /// Performance: Only notifies listeners if data actually changed
  void updateProjects(List<Project> projects) {
    if (_projects == projects) return; // Early exit if data hasn't changed
    _projects = projects;
    _buildDataGridRows();
    _rowAdapterCache.clear(); // Clear cache when data changes
    notifyListeners();
  }

  /// Build data grid rows from projects
  void _buildDataGridRows() {
    _dataGridRows = _projects.map<DataGridRow>((project) {
      final updatedTimestamp = project.sourceModUpdated ?? project.updatedAt;
      final updatedDate = DateTime.fromMillisecondsSinceEpoch(
        updatedTimestamp * 1000,
      );

      return DataGridRow(
        cells: [
          DataGridCell<String?>(
            columnName: 'image',
            value: project.imageUrl,
          ),
          DataGridCell<String>(
            columnName: 'workshop_id',
            value: project.modSteamId ?? '-',
          ),
          DataGridCell<String>(
            columnName: 'name',
            value: project.displayName,
          ),
          DataGridCell<String>(
            columnName: 'version',
            value: project.modVersion ?? '-',
          ),
          DataGridCell<String>(
            columnName: 'status',
            value: project.statusDisplay,
          ),
          DataGridCell<DateTime>(
            columnName: 'updated',
            value: updatedDate,
          ),
          DataGridCell<String>(
            columnName: 'id',
            value: project.id,
          ),
        ],
      );
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final imageUrl = row.getCells()[0].value as String?;
    final workshopId = row.getCells()[1].value.toString();
    final modName = row.getCells()[2].value.toString();
    final version = row.getCells()[3].value.toString();
    final status = row.getCells()[4].value as String;
    final updatedDate = row.getCells()[5].value as DateTime;
    final timeAgo = timeago.format(updatedDate);

    // Performance: Wrap each cell in RepaintBoundary to isolate repaints
    return DataGridRowAdapter(
      cells: [
        // Mod Image
        RepaintBoundary(
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.all(4),
            child: _ModImage(imageUrl: imageUrl),
          ),
        ),
        // Workshop ID
        RepaintBoundary(
          child: _DataGridCell(
            text: workshopId,
            fontFamily: 'monospace',
          ),
        ),
        // Mod Name
        RepaintBoundary(
          child: _DataGridCell(
            text: modName,
            fontWeight: FontWeight.w600,
          ),
        ),
        // Version
        RepaintBoundary(
          child: _DataGridCell(
            text: version,
            fontFamily: 'monospace',
          ),
        ),
        // Status Badge
        RepaintBoundary(
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(8),
            child: _StatusBadge(status: status),
          ),
        ),
        // Last Updated
        RepaintBoundary(
          child: _DataGridCell(text: timeAgo),
        ),
      ],
    );
  }

  @override
  Future<void> handleLoadMoreRows() async {
    // Pagination support - can be implemented later
    await Future.delayed(const Duration(seconds: 1));
    notifyListeners();
  }

  @override
  Future<bool> handlePageChange(int oldPageIndex, int newPageIndex) async {
    // Page change support - can be implemented later
    return true;
  }
}

/// Performance-optimized DataGrid cell widget with const constructor
class _DataGridCell extends StatelessWidget {
  final String text;
  final FontWeight? fontWeight;
  final String? fontFamily;

  const _DataGridCell({
    required this.text,
    this.fontWeight,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: fontWeight,
              fontFamily: fontFamily,
            ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Mod image widget for the DataGrid
class _ModImage extends StatelessWidget {
  final String? imageUrl;

  const _ModImage({this.imageUrl});

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          FluentIcons.image_off_24_regular,
          size: 24,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Check if it's a local file path or a URL
    final isLocalFile = !imageUrl!.startsWith('http://') && 
                        !imageUrl!.startsWith('https://');

    if (isLocalFile) {
      // Display local image file
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.file(
          File(imageUrl!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              FluentIcons.image_alt_text_24_regular,
              size: 24,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Display network image
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: imageUrl!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          width: 48,
          height: 48,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
        errorWidget: (context, url, error) => Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            FluentIcons.image_alt_text_24_regular,
            size: 24,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// Status badge widget for the DataGrid
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color badgeColor;
    final Color textColor;

    switch (status.toLowerCase()) {
      case 'draft':
        badgeColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.colorScheme.onSurface;
        break;
      case 'translating':
        badgeColor = theme.colorScheme.primaryContainer;
        textColor = theme.colorScheme.onPrimaryContainer;
        break;
      case 'reviewing':
        badgeColor = theme.colorScheme.tertiaryContainer;
        textColor = theme.colorScheme.onTertiaryContainer;
        break;
      case 'completed':
        badgeColor = theme.colorScheme.secondaryContainer;
        textColor = theme.colorScheme.onSecondaryContainer;
        break;
      default:
        badgeColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.colorScheme.onSurface;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
