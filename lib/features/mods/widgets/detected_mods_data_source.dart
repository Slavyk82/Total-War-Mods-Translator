import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// Data source for Syncfusion DataGrid displaying detected mods
class DetectedModsDataSource extends DataGridSource {
  DetectedModsDataSource({
    required List<DetectedMod> mods,
    required this.onRowTap,
  }) {
    _mods = mods;
    _buildDataGridRows();
  }

  List<DetectedMod> _mods = [];
  List<DataGridRow> _dataGridRows = [];
  final Function(String workshopId) onRowTap;

  @override
  List<DataGridRow> get rows => _dataGridRows;

  /// Update the data source with new mods
  void updateMods(List<DetectedMod> mods) {
    if (_mods == mods) return;
    _mods = mods;
    _buildDataGridRows();
    notifyListeners();
  }

  /// Build data grid rows from mods
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
          DataGridCell<_LastUpdatedData>(
            columnName: 'last_updated',
            value: _LastUpdatedData(
              timeUpdated: mod.timeUpdated,
              needsUpdate: mod.needsUpdate,
            ),
          ),
          DataGridCell<bool>(
            columnName: 'imported',
            value: mod.isAlreadyImported,
          ),
          DataGridCell<ModUpdateAnalysis?>(
            columnName: 'changes',
            value: mod.updateAnalysis,
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
    final subscribers = row.getCells()[3].value as int;
    final lastUpdatedData = row.getCells()[4].value as _LastUpdatedData;
    final isImported = row.getCells()[5].value as bool;
    final updateAnalysis = row.getCells()[6].value as ModUpdateAnalysis?;

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
        // Subscribers
        RepaintBoundary(
          child: _DataGridCell(
            text: subscribers > 0 
                ? NumberFormat('#,###', 'en_US').format(subscribers).replaceAll(',', ' ')
                : '-',
          ),
        ),
        // Last Updated
        RepaintBoundary(
          child: _LastUpdatedCell(data: lastUpdatedData),
        ),
        // Imported Status
        RepaintBoundary(
          child: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.all(8),
            child: _ImportedBadge(isImported: isImported),
          ),
        ),
        // Changes Analysis
        RepaintBoundary(
          child: _ChangesCell(analysis: updateAnalysis, isImported: isImported),
        ),
      ],
    );
  }
}

/// Data class for last updated cell
class _LastUpdatedData {
  final int? timeUpdated;
  final bool needsUpdate;

  const _LastUpdatedData({
    this.timeUpdated,
    this.needsUpdate = false,
  });
}

/// Last updated cell widget with update indicator
class _LastUpdatedCell extends StatelessWidget {
  final _LastUpdatedData data;

  const _LastUpdatedCell({required this.data});

  /// Format the number of days since the last update
  String _formatDaysSinceUpdate(DateTime updatedDate) {
    final now = DateTime.now();
    final difference = now.difference(updatedDate);
    final days = difference.inDays;

    if (days == 0) {
      final hours = difference.inHours;
      if (hours == 0) {
        return '< 1h';
      }
      return '${hours}h';
    } else if (days == 1) {
      return '1 day';
    } else if (days < 30) {
      return '$days days';
    } else if (days < 365) {
      final months = (days / 30).floor();
      return months == 1 ? '1 month' : '$months months';
    } else {
      final years = (days / 365).floor();
      return years == 1 ? '1 year' : '$years years';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (data.timeUpdated == null || data.timeUpdated == 0) {
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Text(
          '-',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }

    final date = DateTime.fromMillisecondsSinceEpoch(data.timeUpdated! * 1000);
    final daysSinceUpdate = _formatDaysSinceUpdate(date);

    if (data.needsUpdate) {
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Tooltip(
          message: 'Steam version is newer than local file.\nLaunch the game to update this mod.',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_circle_24_filled,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  daysSinceUpdate,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      child: Text(
        daysSinceUpdate,
        style: theme.textTheme.bodyMedium,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Performance-optimized DataGrid cell widget
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

/// Imported status badge widget
class _ImportedBadge extends StatelessWidget {
  final bool isImported;

  const _ImportedBadge({required this.isImported});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!isImported) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Not Imported',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            size: 14,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 4),
          Text(
            'Imported',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Changes analysis cell widget
class _ChangesCell extends StatelessWidget {
  final ModUpdateAnalysis? analysis;
  final bool isImported;

  const _ChangesCell({
    required this.analysis,
    required this.isImported,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Not imported - no analysis
    if (!isImported) {
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Text(
          '-',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Imported but no analysis available
    if (analysis == null) {
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Text(
          'Analyzing...',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    // No changes
    if (!analysis!.hasChanges) {
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 4),
            Text(
              'Up to date',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      );
    }

    // Has changes - build tooltip with details
    final tooltipLines = <String>[];
    if (analysis!.hasNewUnits) {
      tooltipLines.add('+${analysis!.newUnitsCount} new translations to add');
    }
    if (analysis!.hasRemovedUnits) {
      tooltipLines.add('-${analysis!.removedUnitsCount} translations removed');
    }
    if (analysis!.hasModifiedUnits) {
      tooltipLines.add('~${analysis!.modifiedUnitsCount} source texts changed');
    }

    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      child: Tooltip(
        message: tooltipLines.join('\n'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.warning_24_filled,
                size: 14,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  analysis!.summary,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

