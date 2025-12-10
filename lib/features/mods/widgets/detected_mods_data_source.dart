import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_status.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart' show NumberFormat;

/// Data source for Syncfusion DataGrid displaying detected mods
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
              localFileLastModified: mod.localFileLastModified,
              updateStatus: mod.updateStatus,
            ),
          ),
          DataGridCell<_ImportedData>(
            columnName: 'imported',
            value: _ImportedData(isImported: mod.isAlreadyImported),
          ),
          DataGridCell<_ChangesData>(
            columnName: 'changes',
            value: _ChangesData(
              analysis: mod.updateAnalysis,
              updateStatus: mod.updateStatus,
              packFilePath: mod.packFilePath,
            ),
          ),
          DataGridCell<_HideData>(
            columnName: 'hide',
            value: _HideData(
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
    final imageUrl = row.getCells()[0].value as String?;
    final workshopId = row.getCells()[1].value.toString();
    final modName = row.getCells()[2].value.toString();
    final subscribers = row.getCells()[3].value as int;
    final lastUpdatedData = row.getCells()[4].value as _LastUpdatedData;
    final importedData = row.getCells()[5].value as _ImportedData;
    final changesData = row.getCells()[6].value as _ChangesData;
    final hideData = row.getCells()[7].value as _HideData;

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
            child: _ImportedBadge(isImported: importedData.isImported),
          ),
        ),
        // Changes Analysis
        RepaintBoundary(
          child: _ChangesCell(
            data: changesData,
            isImported: importedData.isImported,
            onForceRedownload: onForceRedownload,
          ),
        ),
        // Hide checkbox
        RepaintBoundary(
          child: _HideCheckbox(
            data: hideData,
            showingHidden: showingHidden,
            onToggle: onToggleHidden,
          ),
        ),
      ],
    );
  }
}

/// Data class for imported status cell
class _ImportedData implements Comparable<_ImportedData> {
  final bool isImported;

  const _ImportedData({required this.isImported});

  @override
  int compareTo(_ImportedData other) {
    // Sort imported items first (true = 0, false = 1)
    return (isImported ? 0 : 1).compareTo(other.isImported ? 0 : 1);
  }
}

/// Data class for last updated cell
class _LastUpdatedData implements Comparable<_LastUpdatedData> {
  final int? timeUpdated;
  final int? localFileLastModified;
  final ModUpdateStatus updateStatus;

  const _LastUpdatedData({
    this.timeUpdated,
    this.localFileLastModified,
    this.updateStatus = ModUpdateStatus.unknown,
  });

  @override
  int compareTo(_LastUpdatedData other) {
    // Sort by timeUpdated (most recent first), nulls last
    final thisTime = timeUpdated ?? 0;
    final otherTime = other.timeUpdated ?? 0;
    return otherTime.compareTo(thisTime);
  }
}

/// Data class for changes cell
class _ChangesData implements Comparable<_ChangesData> {
  final ModUpdateAnalysis? analysis;
  final ModUpdateStatus updateStatus;
  final String packFilePath;

  const _ChangesData({
    this.analysis,
    this.updateStatus = ModUpdateStatus.unknown,
    required this.packFilePath,
  });

  @override
  int compareTo(_ChangesData other) {
    // Sort by update status priority (hasChanges > needsDownload > upToDate > unknown)
    final statusPriority = {
      ModUpdateStatus.hasChanges: 0,
      ModUpdateStatus.needsDownload: 1,
      ModUpdateStatus.upToDate: 2,
      ModUpdateStatus.unknown: 3,
    };
    final thisPriority = statusPriority[updateStatus] ?? 3;
    final otherPriority = statusPriority[other.updateStatus] ?? 3;
    if (thisPriority != otherPriority) {
      return thisPriority.compareTo(otherPriority);
    }
    // If same status, sort by total changes count
    final thisCount = _getTotalChanges(analysis);
    final otherCount = _getTotalChanges(other.analysis);
    return otherCount.compareTo(thisCount);
  }

  int _getTotalChanges(ModUpdateAnalysis? analysis) {
    if (analysis == null) return 0;
    return analysis.newUnitsCount +
        analysis.removedUnitsCount +
        analysis.modifiedUnitsCount;
  }
}

/// Data class for hide cell
class _HideData implements Comparable<_HideData> {
  final String workshopId;
  final bool isHidden;

  const _HideData({
    required this.workshopId,
    required this.isHidden,
  });

  @override
  int compareTo(_HideData other) {
    // Sort hidden items first (true = 0, false = 1)
    return (isHidden ? 0 : 1).compareTo(other.isHidden ? 0 : 1);
  }
}

/// Last updated cell widget with update indicator
class _LastUpdatedCell extends StatelessWidget {
  final _LastUpdatedData data;

  const _LastUpdatedCell({required this.data});

  /// Format the time since a date in a human-readable way
  String _formatTimeSince(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
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

  /// Format a date for tooltip display
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Build detailed tooltip with Steam and local dates
  String _buildTooltip() {
    final lines = <String>[];

    if (data.timeUpdated != null && data.timeUpdated! > 0) {
      final steamDate = DateTime.fromMillisecondsSinceEpoch(data.timeUpdated! * 1000);
      lines.add('Steam Workshop: ${_formatDate(steamDate)}');
    }

    if (data.localFileLastModified != null && data.localFileLastModified! > 0) {
      final localDate = DateTime.fromMillisecondsSinceEpoch(data.localFileLastModified! * 1000);
      lines.add('Local file: ${_formatDate(localDate)}');
    }

    return lines.join('\n');
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

    // Always display Steam Workshop update date in this column
    final steamDate = DateTime.fromMillisecondsSinceEpoch(data.timeUpdated! * 1000);
    final timeSinceSteamUpdate = _formatTimeSince(steamDate);

    // Show download required alert (red) when local file is outdated
    if (data.updateStatus == ModUpdateStatus.needsDownload) {
      final tooltipLines = [
        'Steam version is newer than local file.',
        'Launch the game to download the update.',
        '',
        _buildTooltip(),
      ];
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Tooltip(
          message: tooltipLines.join('\n'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_download_24_filled,
                size: 16,
                color: theme.colorScheme.error,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  timeSinceSteamUpdate,
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

    // Show changes detected indicator (orange/warning) when local file is current but has changes
    if (data.updateStatus == ModUpdateStatus.hasChanges) {
      final tooltipLines = [
        'Translation differences detected between source and project.',
        'Review changes to synchronize your translations.',
        '',
        _buildTooltip(),
      ];
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Tooltip(
          message: tooltipLines.join('\n'),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_24_filled,
                size: 16,
                color: theme.colorScheme.tertiary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  timeSinceSteamUpdate,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.tertiary,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Normal display - no issues
    return Container(
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.all(8),
      child: Tooltip(
        message: _buildTooltip(),
        child: Text(
          timeSinceSteamUpdate,
          style: theme.textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
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
  final _ChangesData data;
  final bool isImported;
  final Function(String packFilePath)? onForceRedownload;

  const _ChangesCell({
    required this.data,
    required this.isImported,
    this.onForceRedownload,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final analysis = data.analysis;
    final updateStatus = data.updateStatus;

    // Not imported - no analysis needed
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

    // Needs download - show clickable badge to delete local file
    if (updateStatus == ModUpdateStatus.needsDownload) {
      return Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.all(8),
        child: Tooltip(
          message: 'Click to delete local file and force redownload',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: onForceRedownload != null
                  ? () => onForceRedownload!(data.packFilePath)
                  : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      FluentIcons.arrow_download_24_filled,
                      size: 14,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Download required',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // Up to date (no new Steam update, so no analysis needed)
    if (updateStatus == ModUpdateStatus.upToDate) {
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

    // Has changes status with analysis available
    if (updateStatus == ModUpdateStatus.hasChanges && analysis != null) {
      // Build tooltip with details
      final tooltipLines = <String>[];
      if (analysis.hasNewUnits) {
        tooltipLines.add('+${analysis.newUnitsCount} new translations to add');
      }
      if (analysis.hasRemovedUnits) {
        tooltipLines.add('-${analysis.removedUnitsCount} translations removed');
      }
      if (analysis.hasModifiedUnits) {
        tooltipLines.add('~${analysis.modifiedUnitsCount} source texts changed');
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
                    analysis.summary,
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

    // Unknown status or still analyzing
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
}

/// Hide checkbox widget for toggling mod visibility
class _HideCheckbox extends StatelessWidget {
  final _HideData data;
  final bool showingHidden;
  final Function(String workshopId, bool hide)? onToggle;

  const _HideCheckbox({
    required this.data,
    required this.showingHidden,
    this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // When showing hidden mods: checkbox is checked (mod is hidden)
    // When showing visible mods: checkbox is unchecked (mod is visible)
    // Clicking toggles the hidden state
    final isChecked = data.isHidden;

    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Tooltip(
        message: showingHidden
            ? 'Uncheck to show this mod in the main list'
            : 'Check to hide this mod from the main list',
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: () {
              if (onToggle != null) {
                // Toggle hidden state
                onToggle!(data.workshopId, !data.isHidden);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isChecked
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isChecked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                  width: 1.5,
                ),
              ),
              child: isChecked
                  ? Icon(
                      FluentIcons.checkmark_16_filled,
                      size: 16,
                      color: theme.colorScheme.onPrimary,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

