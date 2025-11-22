import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/providers/mods/mod_update_provider.dart';

/// Dialog showing progress of mod updates
class ModUpdateDialog extends ConsumerWidget {
  const ModUpdateDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final updateQueue = ref.watch(modUpdateQueueProvider);
    final allComplete = ref.read(modUpdateQueueProvider.notifier).allComplete;

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 700,
          maxHeight: 600,
        ),
        child: Column(
          children: [
            // Header
            _buildHeader(context, updateQueue.length, allComplete),
            const Divider(height: 1),

            // Content
            Expanded(
              child: updateQueue.isEmpty
                  ? _buildEmptyState(context)
                  : _buildUpdateList(context, updateQueue.values.toList()),
            ),

            // Footer
            const Divider(height: 1),
            _buildFooter(context, ref, allComplete),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int totalUpdates, bool allComplete) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: allComplete
                  ? const Color(0xFF107C10).withValues(alpha: 0.1)
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              allComplete
                  ? FluentIcons.checkmark_circle_24_regular
                  : FluentIcons.arrow_download_24_regular,
              color: allComplete
                  ? const Color(0xFF107C10)
                  : theme.colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  allComplete ? 'Updates Complete' : 'Updating Mods',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  allComplete
                      ? 'All updates have been processed'
                      : 'Updating $totalUpdates ${totalUpdates == 1 ? 'mod' : 'mods'}...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateList(BuildContext context, List<ModUpdateInfo> updates) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      itemCount: updates.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _UpdateItem(updateInfo: updates[index]);
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.archive_24_regular,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No Updates',
            style: theme.textTheme.titleLarge?.copyWith(
              color: theme.textTheme.bodyMedium?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'No mods in update queue',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, WidgetRef ref, bool allComplete) {
    final theme = Theme.of(context);
    final completedCount = ref.read(modUpdateQueueProvider.notifier).completedCount;
    final failedCount = ref.read(modUpdateQueueProvider.notifier).failedCount;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!allComplete)
            // Progress summary
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Progress: $completedCount completed, $failedCount failed',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                ),
              ],
            ),
          if (!allComplete) const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              if (!allComplete)
                Expanded(
                  child: _SecondaryButton(
                    label: 'Cancel',
                    onTap: () {
                      ref.read(modUpdateQueueProvider.notifier).cancelAll();
                    },
                  ),
                ),
              if (!allComplete) const SizedBox(width: 12),
              Expanded(
                child: _PrimaryButton(
                  label: allComplete ? 'Close' : 'Hide',
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UpdateItem extends ConsumerWidget {
  final ModUpdateInfo updateInfo;

  const _UpdateItem({required this.updateInfo});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with mod name and status
          Row(
            children: [
              Icon(
                FluentIcons.cube_24_regular,
                color: theme.colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  updateInfo.projectName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _StatusBadge(status: updateInfo.status),
            ],
          ),
          const SizedBox(height: 12),

          // Status message
          Text(
            _getStatusMessage(updateInfo.status),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.textTheme.bodySmall?.color,
            ),
          ),

          // Progress bar (only for in-progress updates)
          if (updateInfo.isInProgress) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: updateInfo.progress,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${(updateInfo.progress * 100).toInt()}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color,
              ),
            ),
          ],

          // Error message
          if (updateInfo.isFailed && updateInfo.errorMessage != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFD13438).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(
                    FluentIcons.error_circle_24_regular,
                    color: Color(0xFFD13438),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      updateInfo.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFD13438),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _RetryButton(
              onTap: () {
                ref
                    .read(modUpdateQueueProvider.notifier)
                    .retry(updateInfo.projectId);
              },
            ),
          ],

          // Success message
          if (updateInfo.isCompleted && updateInfo.newVersion != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF107C10).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(
                    FluentIcons.checkmark_circle_24_regular,
                    color: Color(0xFF107C10),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Updated to version ${updateInfo.newVersion!.versionString}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF107C10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getStatusMessage(ModUpdateStatus status) {
    switch (status) {
      case ModUpdateStatus.pending:
        return 'Waiting to start...';
      case ModUpdateStatus.downloading:
        return 'Downloading from Steam Workshop...';
      case ModUpdateStatus.detectingChanges:
        return 'Detecting changes...';
      case ModUpdateStatus.updatingDatabase:
        return 'Updating database...';
      case ModUpdateStatus.completed:
        return 'Successfully updated';
      case ModUpdateStatus.failed:
        return 'Update failed';
      case ModUpdateStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final ModUpdateStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    Color textColor;
    IconData icon;
    String label;

    switch (status) {
      case ModUpdateStatus.pending:
        backgroundColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
        icon = FluentIcons.clock_24_regular;
        label = 'PENDING';
        break;
      case ModUpdateStatus.downloading:
      case ModUpdateStatus.detectingChanges:
      case ModUpdateStatus.updatingDatabase:
        backgroundColor = theme.colorScheme.primaryContainer;
        textColor = theme.colorScheme.primary;
        icon = FluentIcons.arrow_download_24_regular;
        label = 'IN PROGRESS';
        break;
      case ModUpdateStatus.completed:
        backgroundColor = const Color(0xFF107C10).withValues(alpha: 0.1);
        textColor = const Color(0xFF107C10);
        icon = FluentIcons.checkmark_circle_24_regular;
        label = 'COMPLETED';
        break;
      case ModUpdateStatus.failed:
        backgroundColor = const Color(0xFFD13438).withValues(alpha: 0.1);
        textColor = const Color(0xFFD13438);
        icon = FluentIcons.error_circle_24_regular;
        label = 'FAILED';
        break;
      case ModUpdateStatus.cancelled:
        backgroundColor = theme.colorScheme.surfaceContainerHighest;
        textColor = theme.textTheme.bodySmall?.color ?? Colors.grey;
        icon = FluentIcons.dismiss_circle_24_regular;
        label = 'CANCELLED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _PrimaryButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isPressed
                ? theme.colorScheme.primary.withValues(alpha: 0.8)
                : _isHovered
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _SecondaryButton({
    required this.label,
    required this.onTap,
  });

  @override
  State<_SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<_SecondaryButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isPressed
                ? theme.colorScheme.surfaceContainerHighest
                : _isHovered
                    ? theme.colorScheme.surfaceContainerHigh
                    : theme.colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Text(
            widget.label,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _RetryButton extends StatefulWidget {
  final VoidCallback onTap;

  const _RetryButton({required this.onTap});

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_clockwise_24_regular,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(
                'Retry',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
