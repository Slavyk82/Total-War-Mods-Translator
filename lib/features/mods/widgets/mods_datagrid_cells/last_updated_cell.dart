import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/models/mods_cell_data.dart';
import 'package:twmt/models/domain/mod_update_status.dart';

/// Last updated cell widget with update indicator.
///
/// Displays the time since the mod was last updated on Steam Workshop,
/// with visual indicators for different update statuses:
/// - Red download icon: Local file needs to be downloaded
/// - Orange sync icon: Changes detected between source and project
/// - Normal text: Up to date or unknown status
class LastUpdatedCell extends StatelessWidget {
  /// The data containing update timestamps and status.
  final LastUpdatedData data;

  const LastUpdatedCell({super.key, required this.data});

  /// Format the time since a date in a human-readable way.
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

  /// Format a date for tooltip display.
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  /// Build detailed tooltip with Steam and local dates.
  String _buildTooltip() {
    final lines = <String>[];

    if (data.timeUpdated != null && data.timeUpdated! > 0) {
      final steamDate =
          DateTime.fromMillisecondsSinceEpoch(data.timeUpdated! * 1000);
      lines.add('Steam Workshop: ${_formatDate(steamDate)}');
    }

    if (data.localFileLastModified != null &&
        data.localFileLastModified! > 0) {
      final localDate =
          DateTime.fromMillisecondsSinceEpoch(data.localFileLastModified! * 1000);
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
    final steamDate =
        DateTime.fromMillisecondsSinceEpoch(data.timeUpdated! * 1000);
    final timeSinceSteamUpdate = _formatTimeSince(steamDate);

    // Show download required alert (red) when local file is outdated
    if (data.updateStatus == ModUpdateStatus.needsDownload) {
      return _buildNeedsDownloadCell(context, theme, timeSinceSteamUpdate);
    }

    // Show changes detected indicator (orange/warning) when local file is
    // current but has changes
    if (data.updateStatus == ModUpdateStatus.hasChanges) {
      return _buildHasChangesCell(context, theme, timeSinceSteamUpdate);
    }

    // Normal display - no issues
    return _buildNormalCell(context, theme, timeSinceSteamUpdate);
  }

  Widget _buildNeedsDownloadCell(
    BuildContext context,
    ThemeData theme,
    String timeSinceSteamUpdate,
  ) {
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

  Widget _buildHasChangesCell(
    BuildContext context,
    ThemeData theme,
    String timeSinceSteamUpdate,
  ) {
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

  Widget _buildNormalCell(
    BuildContext context,
    ThemeData theme,
    String timeSinceSteamUpdate,
  ) {
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
