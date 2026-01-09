import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/mods/models/mods_cell_data.dart';
import 'package:twmt/models/domain/mod_update_status.dart';

/// Changes analysis cell widget.
///
/// Displays the update status and change analysis for a mod:
/// - "-" for not imported mods (no analysis needed)
/// - "Download required" clickable badge for outdated local files
/// - "Up to date" for mods with no pending changes
/// - Change summary badge showing new/removed/modified counts
class ChangesCell extends StatelessWidget {
  /// The data containing analysis results and update status.
  final ChangesData data;

  /// Whether the mod has been imported.
  final bool isImported;

  /// Callback for forcing a redownload of the mod.
  final void Function(String packFilePath)? onForceRedownload;

  const ChangesCell({
    super.key,
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
      return _buildDashCell(theme);
    }

    // Needs download - show clickable badge to delete local file
    if (updateStatus == ModUpdateStatus.needsDownload) {
      return _buildNeedsDownloadCell(context, theme);
    }

    // Up to date (no new Steam update, so no analysis needed)
    if (updateStatus == ModUpdateStatus.upToDate) {
      return _buildUpToDateCell(theme);
    }

    // Has changes status with analysis available
    if (updateStatus == ModUpdateStatus.hasChanges && analysis != null) {
      return _buildHasChangesCell(theme);
    }

    // Unknown status or still analyzing
    return _buildDashCell(theme);
  }

  Widget _buildDashCell(ThemeData theme) {
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

  Widget _buildNeedsDownloadCell(BuildContext context, ThemeData theme) {
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

  Widget _buildUpToDateCell(ThemeData theme) {
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

  Widget _buildHasChangesCell(ThemeData theme) {
    final analysis = data.analysis!;

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
}
