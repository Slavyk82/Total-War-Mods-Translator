import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../config/app_constants.dart';
import '../../../models/history/diff_models.dart';
import '../../../providers/history/history_providers.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Dialog for comparing two translation versions side by side
///
/// Shows:
/// - Metadata for each version (timestamp, changed by)
/// - Side-by-side text with diff highlighting
/// - Statistics (chars/words added/removed)
/// - Actions (copy, restore)
class VersionComparisonDialog extends ConsumerStatefulWidget {
  final String historyId1; // Older version (left)
  final String historyId2; // Newer version (right)
  final String versionId;

  const VersionComparisonDialog({
    super.key,
    required this.historyId1,
    required this.historyId2,
    required this.versionId,
  });

  @override
  ConsumerState<VersionComparisonDialog> createState() =>
      _VersionComparisonDialogState();
}

class _VersionComparisonDialogState
    extends ConsumerState<VersionComparisonDialog> {
  final ScrollController _leftScrollController = ScrollController();
  final ScrollController _rightScrollController = ScrollController();
  final bool _syncScrolling = true;

  @override
  void initState() {
    super.initState();
    _setupScrollSync();
  }

  void _setupScrollSync() {
    _leftScrollController.addListener(() {
      if (_syncScrolling && _leftScrollController.hasClients) {
        _rightScrollController
            .jumpTo(_leftScrollController.offset);
      }
    });

    _rightScrollController.addListener(() {
      if (_syncScrolling && _rightScrollController.hasClients) {
        _leftScrollController
            .jumpTo(_rightScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _leftScrollController.dispose();
    _rightScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final comparisonAsync = ref.watch(
      versionComparisonProvider(widget.historyId1, widget.historyId2),
    );

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.8,
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(context),

            // Content
            Expanded(
              child: comparisonAsync.when(
                data: (comparison) => _buildComparison(context, comparison),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => _buildError(context, error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.document_text_link_24_regular,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'Compare Versions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Icon(
                FluentIcons.dismiss_24_regular,
                size: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparison(BuildContext context, VersionComparison comparison) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Side-by-side comparison
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left side (older version)
              Expanded(
                child: _buildVersionPanel(
                  context,
                  comparison.version1,
                  'Old Version',
                  comparison.diff,
                  true,
                  _leftScrollController,
                ),
              ),

              // Divider
              Container(
                width: 1,
                color: Theme.of(context).dividerColor,
              ),

              // Right side (newer version)
              Expanded(
                child: _buildVersionPanel(
                  context,
                  comparison.version2,
                  'New Version',
                  comparison.diff,
                  false,
                  _rightScrollController,
                ),
              ),
            ],
          ),
        ),

        // Statistics
        _buildStatistics(context, comparison.stats),

        // Actions
        _buildActions(context, comparison),
      ],
    );
  }

  Widget _buildVersionPanel(
    BuildContext context,
    dynamic version,
    String title,
    List<DiffSegment> diff,
    bool isOld,
    ScrollController scrollController,
  ) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      version.createdAt * 1000,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Panel header
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 1,
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(
                    version.isUserChange
                        ? FluentIcons.person_24_regular
                        : FluentIcons.bot_24_regular,
                    size: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    version.changedByDisplay,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    timeago.format(timestamp),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Text content with highlighting
        Expanded(
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(16),
            child: SelectableText.rich(
              _buildDiffTextSpan(context, diff, isOld),
            ),
          ),
        ),
      ],
    );
  }

  TextSpan _buildDiffTextSpan(
    BuildContext context,
    List<DiffSegment> diff,
    bool isOld,
  ) {
    final spans = <TextSpan>[];

    for (final segment in diff) {
      Color? backgroundColor;
      TextDecoration? decoration;

      if (isOld) {
        // Old version: highlight removed text
        if (segment.type == DiffType.removed) {
          backgroundColor = Colors.red.withValues(alpha: 0.3);
          decoration = TextDecoration.lineThrough;
        } else if (segment.type == DiffType.added) {
          // Skip added text in old version
          continue;
        }
      } else {
        // New version: highlight added text
        if (segment.type == DiffType.added) {
          backgroundColor = Colors.green.withValues(alpha: 0.3);
        } else if (segment.type == DiffType.removed) {
          // Skip removed text in new version
          continue;
        }
      }

      spans.add(
        TextSpan(
          text: segment.text,
          style: TextStyle(
            backgroundColor: backgroundColor,
            decoration: decoration,
            fontFamily: 'monospace',
          ),
        ),
      );
    }

    return TextSpan(children: spans);
  }

  Widget _buildStatistics(BuildContext context, DiffStats stats) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Changes',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildStatItem(
                context,
                'Characters Added',
                stats.charsAdded.toString(),
                Colors.green,
              ),
              _buildStatItem(
                context,
                'Characters Removed',
                stats.charsRemoved.toString(),
                Colors.red,
              ),
              _buildStatItem(
                context,
                'Words Added',
                stats.wordsAdded.toString(),
                Colors.green,
              ),
              _buildStatItem(
                context,
                'Words Removed',
                stats.wordsRemoved.toString(),
                Colors.red,
              ),
              _buildStatItem(
                context,
                'Total Changes',
                stats.charsChanged.toString(),
                Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, VersionComparison comparison) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          _buildActionButton(
            context,
            'Copy Old',
            FluentIcons.copy_24_regular,
            () => _copyToClipboard(comparison.version1.translatedText),
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            'Copy New',
            FluentIcons.copy_24_regular,
            () => _copyToClipboard(comparison.version2.translatedText),
          ),
          const Spacer(),
          _buildActionButton(
            context,
            'Restore Old',
            FluentIcons.arrow_undo_24_regular,
            () => _restoreVersion(context, comparison.version1),
            isPrimary: true,
          ),
          const SizedBox(width: 8),
          _buildActionButton(
            context,
            'Close',
            FluentIcons.dismiss_24_regular,
            () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool isPrimary = false,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isPrimary
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isPrimary
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isPrimary
                    ? Theme.of(context).colorScheme.onPrimary
                    : Theme.of(context).colorScheme.onSurface,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isPrimary
                          ? Theme.of(context).colorScheme.onPrimary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to compare versions',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      FluentToast.success(context, 'Copied to clipboard');
    }
  }

  Future<void> _restoreVersion(BuildContext context, dynamic version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Version'),
        content: Text(
          'Are you sure you want to restore this version?\n\n'
          'Preview:\n"${version.getTranslatedTextPreview(100)}"',
        ),
        actions: [
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FluentTextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final service = ref.read(historyServiceProvider);
      final result = await service.revertToVersion(
        versionId: widget.versionId,
        historyId: version.id,
        changedBy: AppConstants.defaultUserId,
      );

      if (mounted) {
        result.when(
          ok: (_) {
            FluentToast.success(context, 'Version restored successfully');
            Navigator.of(context).pop();
          },
          err: (error) {
            FluentToast.error(context, 'Failed to restore: $error');
          },
        );
      }
    }
  }
}
