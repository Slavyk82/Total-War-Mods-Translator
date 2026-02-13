import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';
import '../providers/batch_workshop_publish_notifier.dart';
import 'steam_guard_dialog.dart';

/// Dialog for batch workshop publish progress.
class BatchWorkshopPublishDialog extends ConsumerStatefulWidget {
  final List<BatchPublishItemInfo> items;
  final String username;
  final String password;
  final String? steamGuardCode;

  const BatchWorkshopPublishDialog({
    super.key,
    required this.items,
    required this.username,
    required this.password,
    this.steamGuardCode,
  });

  @override
  ConsumerState<BatchWorkshopPublishDialog> createState() =>
      _BatchWorkshopPublishDialogState();
}

class _BatchWorkshopPublishDialogState
    extends ConsumerState<BatchWorkshopPublishDialog> {
  final DateTime _startTime = DateTime.now();
  bool _steamGuardDialogShown = false;
  late final BatchWorkshopPublishNotifier _publishNotifier;

  @override
  void initState() {
    super.initState();
    _publishNotifier = ref.read(batchWorkshopPublishProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _publishNotifier.publishBatch(
            items: widget.items,
            username: widget.username,
            password: widget.password,
            steamGuardCode: widget.steamGuardCode,
          );
    });
  }

  @override
  void dispose() {
    _publishNotifier.silentCleanup();
    super.dispose();
  }

  String get _elapsedTime {
    final elapsed = DateTime.now().difference(_startTime);
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(batchWorkshopPublishProvider);

    // Handle Steam Guard
    if (state.needsSteamGuard && !_steamGuardDialogShown) {
      _steamGuardDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final code = await SteamGuardDialog.show(context);
        if (!mounted) return;
        _steamGuardDialogShown = false;
        if (code != null) {
          ref
              .read(batchWorkshopPublishProvider.notifier)
              .retryWithSteamGuard(code);
        } else {
          ref.read(batchWorkshopPublishProvider.notifier).cancel();
        }
      });
    }

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme, state),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProgressSection(theme, state),
                    const SizedBox(height: 20),
                    _buildItemList(theme, state),
                    if (state.isComplete) ...[
                      const SizedBox(height: 20),
                      _buildResultsSummary(theme, state),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildFooter(theme, state),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, BatchWorkshopPublishState state) {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            FluentIcons.cloud_arrow_up_24_regular,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Batch Publish',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${widget.items.length} items',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  FluentIcons.timer_24_regular,
                  size: 14,
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  _elapsedTime,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSection(
      ThemeData theme, BatchWorkshopPublishState state) {
    final progressPercent = (state.overallProgress * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                state.isComplete
                    ? 'Publish Complete'
                    : state.isCancelled
                        ? 'Cancelled'
                        : state.needsSteamGuard
                            ? 'Steam Guard Required'
                            : 'Publishing...',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$progressPercent%',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: state.isComplete && state.failedCount == 0
                      ? Colors.green.shade700
                      : state.failedCount > 0
                          ? Colors.orange.shade700
                          : theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FluentProgressBar(
            value: state.overallProgress,
            height: 8,
            color: state.isComplete && state.failedCount == 0
                ? Colors.green.shade700
                : state.failedCount > 0
                    ? Colors.orange.shade700
                    : theme.colorScheme.primary,
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
          const SizedBox(height: 8),
          Text(
            '${state.completedItems} / ${state.totalItems} items',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (state.currentItemName != null && state.isPublishing) ...[
            const SizedBox(height: 4),
            Text(
              'Current: ${state.currentItemName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemList(ThemeData theme, BatchWorkshopPublishState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 250),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: widget.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = widget.items[index];
              final status = state.itemStatuses[item.name] ??
                  BatchPublishStatus.pending;
              final result = state.results
                  .cast<BatchPublishItemResult?>()
                  .firstWhere(
                    (r) => r?.name == item.name,
                    orElse: () => null,
                  );

              return _PublishStatusItem(
                name: item.name,
                status: status,
                result: result,
                isCurrentItem: state.currentItemName == item.name,
                currentProgress: state.currentItemName == item.name
                    ? state.currentItemProgress
                    : null,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsSummary(
      ThemeData theme, BatchWorkshopPublishState state) {
    final hasFailures = state.failedCount > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: hasFailures
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasFailures
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.green.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasFailures
                ? FluentIcons.warning_24_regular
                : FluentIcons.checkmark_circle_24_regular,
            size: 24,
            color:
                hasFailures ? Colors.orange.shade700 : Colors.green.shade700,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasFailures
                      ? 'Publish completed with errors'
                      : 'All items published successfully',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: hasFailures
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${state.successCount} succeeded, ${state.failedCount} failed',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: hasFailures
                        ? Colors.orange.shade700
                        : Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme, BatchWorkshopPublishState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (state.isPublishing && !state.isCancelled)
            TextButton.icon(
              onPressed: () {
                ref.read(batchWorkshopPublishProvider.notifier).cancel();
              },
              icon: const Icon(FluentIcons.dismiss_24_regular, size: 18),
              label: const Text('Cancel'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
            ),
          if (state.isComplete || state.isCancelled) ...[
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(FluentIcons.checkmark_24_regular, size: 18),
              label: const Text('Close'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Individual item status in the list
class _PublishStatusItem extends StatelessWidget {
  final String name;
  final BatchPublishStatus status;
  final BatchPublishItemResult? result;
  final bool isCurrentItem;
  final double? currentProgress;

  const _PublishStatusItem({
    required this.name,
    required this.status,
    this.result,
    this.isCurrentItem = false,
    this.currentProgress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isCurrentItem
          ? theme.colorScheme.primary.withValues(alpha: 0.05)
          : null,
      child: Row(
        children: [
          _buildStatusIcon(theme),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        isCurrentItem ? FontWeight.w600 : FontWeight.w400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (result != null && result!.success && result!.workshopId != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Workshop ID: ${result!.workshopId}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.5),
                      fontSize: 11,
                    ),
                  ),
                ],
                if (result != null &&
                    !result!.success &&
                    result!.errorMessage != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    result!.errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (isCurrentItem && currentProgress != null) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 60,
              child: FluentProgressBar(
                value: currentProgress!,
                height: 4,
                color: theme.colorScheme.primary,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIcon(ThemeData theme) {
    switch (status) {
      case BatchPublishStatus.pending:
        return Icon(
          FluentIcons.circle_24_regular,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        );
      case BatchPublishStatus.inProgress:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: theme.colorScheme.primary,
          ),
        );
      case BatchPublishStatus.success:
        return Icon(
          FluentIcons.checkmark_circle_24_filled,
          size: 18,
          color: Colors.green.shade700,
        );
      case BatchPublishStatus.failed:
        return Icon(
          FluentIcons.error_circle_24_filled,
          size: 18,
          color: theme.colorScheme.error,
        );
      case BatchPublishStatus.cancelled:
        return Icon(
          FluentIcons.dismiss_circle_24_regular,
          size: 18,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
        );
    }
  }
}
