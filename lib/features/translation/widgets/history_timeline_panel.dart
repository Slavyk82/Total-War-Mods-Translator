import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../../config/app_constants.dart';
import '../../../models/domain/translation_version_history.dart';
import '../../../models/domain/translation_version.dart';
import '../../../providers/history/history_providers.dart';
import 'version_comparison_dialog.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Timeline panel showing history of changes for a translation version
///
/// Displays a vertical timeline with all changes, including:
/// - Version number
/// - Translated text preview
/// - Status badge
/// - Changed by (user/LLM)
/// - Timestamp
/// - Actions (restore, compare)
class HistoryTimelinePanel extends ConsumerWidget {
  final String versionId;
  final String currentTranslatedText;
  final VoidCallback? onClose;

  const HistoryTimelinePanel({
    super.key,
    required this.versionId,
    required this.currentTranslatedText,
    this.onClose,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(versionHistoryProvider(versionId));

    return Container(
      width: 400,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          _buildHeader(context),

          // Content
          Expanded(
            child: historyAsync.when(
              data: (history) => _buildTimeline(context, ref, history),
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (error, stack) => _buildError(context, error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
            FluentIcons.history_24_regular,
            size: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'History Timeline',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          if (onClose != null)
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: onClose,
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

  Widget _buildTimeline(
    BuildContext context,
    WidgetRef ref,
    List<TranslationVersionHistory> history,
  ) {
    if (history.isEmpty) {
      return _buildEmptyState(context);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: history.length + 1, // +1 for current version
      itemBuilder: (context, index) {
        if (index == 0) {
          // Current version
          return _buildCurrentVersionItem(context, ref);
        } else {
          // Historical version
          final entry = history[index - 1];
          final isLast = index == history.length;
          final previousEntry = index < history.length ? history[index] : null;

          return _buildHistoryItem(
            context,
            ref,
            entry,
            index,
            isLast,
            previousEntry,
          );
        }
      },
    );
  }

  Widget _buildCurrentVersionItem(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: 2,
                height: 24,
                color: Theme.of(context).dividerColor,
              ),
            ],
          ),

          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Current',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'Latest',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  currentTranslatedText.length > 100
                      ? '${currentTranslatedText.substring(0, 100)}...'
                      : currentTranslatedText,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(
    BuildContext context,
    WidgetRef ref,
    TranslationVersionHistory entry,
    int index,
    bool isLast,
    TranslationVersionHistory? previousEntry,
  ) {
    final timestamp = DateTime.fromMillisecondsSinceEpoch(
      entry.createdAt * 1000,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                    width: 2,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 24,
                  color: Theme.of(context).dividerColor,
                ),
            ],
          ),

          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Version number and timestamp
                Row(
                  children: [
                    Text(
                      'Version $index',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    Text(
                      timeago.format(timestamp),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),

                const SizedBox(height: 4),

                // Changed by
                Row(
                  children: [
                    Icon(
                      entry.isUserChange
                          ? FluentIcons.person_24_regular
                          : FluentIcons.bot_24_regular,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.changedByDisplay,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(context, entry.status),
                  ],
                ),

                const SizedBox(height: 8),

                // Translated text
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                  child: Text(
                    entry.getTranslatedTextPreview(80),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),

                // Change reason
                if (entry.hasChangeReason) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Reason: ${entry.changeReason}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],

                const SizedBox(height: 8),

                // Actions
                Row(
                  children: [
                    _buildActionButton(
                      context,
                      'Restore',
                      FluentIcons.arrow_undo_24_regular,
                      () => _onRestore(context, ref, entry),
                    ),
                    const SizedBox(width: 8),
                    if (previousEntry != null)
                      _buildActionButton(
                        context,
                        'Compare',
                        FluentIcons.document_text_link_24_regular,
                        () => _onCompare(context, entry, previousEntry),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    BuildContext context,
    TranslationVersionStatus status,
  ) {
    Color color;
    switch (status) {
      case TranslationVersionStatus.pending:
        color = Colors.grey;
        break;
      case TranslationVersionStatus.translated:
        color = Colors.green;
        break;
      case TranslationVersionStatus.needsReview:
        color = Colors.orange;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(
        status.name,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.history_24_regular,
            size: 48,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No history available',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Changes will appear here as you edit',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
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
            'Failed to load history',
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

  Future<void> _onRestore(
    BuildContext context,
    WidgetRef ref,
    TranslationVersionHistory entry,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore Version'),
        content: Text(
          'Are you sure you want to restore this version?\n\n'
          'This will replace the current translation with:\n'
          '"${entry.getTranslatedTextPreview(100)}"',
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

    if (confirmed == true && context.mounted) {
      final service = ref.read(historyServiceProvider);
      final result = await service.revertToVersion(
        versionId: versionId,
        historyId: entry.id,
        changedBy: AppConstants.defaultUserId,
      );

      if (context.mounted) {
        result.when(
          ok: (_) {
            FluentToast.success(context, 'Version restored successfully');
            // Refresh history
            ref.invalidate(versionHistoryProvider(versionId));
          },
          err: (error) {
            FluentToast.error(context, 'Failed to restore: $error');
          },
        );
      }
    }
  }

  Future<void> _onCompare(
    BuildContext context,
    TranslationVersionHistory entry1,
    TranslationVersionHistory entry2,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => VersionComparisonDialog(
        historyId1: entry2.id, // Older version (left)
        historyId2: entry1.id, // Newer version (right)
        versionId: versionId,
      ),
    );
  }
}
