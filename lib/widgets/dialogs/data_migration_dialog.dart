import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../providers/data_migration_provider.dart';

/// Modal dialog that shows data migration progress.
///
/// This dialog is non-dismissible and blocks the UI until migrations complete.
class DataMigrationDialog extends ConsumerStatefulWidget {
  const DataMigrationDialog({super.key});

  /// Show the migration dialog and wait for completion
  static Future<void> showAndRun(BuildContext context, WidgetRef ref) async {
    // Check if migration is needed
    final needsMigration =
        await ref.read(dataMigrationProvider.notifier).needsMigration();

    if (!needsMigration) return;

    if (!context.mounted) return;

    // Show the dialog
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (context) => const DataMigrationDialog(),
    );
  }

  @override
  ConsumerState<DataMigrationDialog> createState() =>
      _DataMigrationDialogState();
}

class _DataMigrationDialogState extends ConsumerState<DataMigrationDialog> {
  @override
  void initState() {
    super.initState();
    // Start migrations when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(dataMigrationProvider.notifier).runMigrations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dataMigrationProvider);
    final theme = Theme.of(context);

    // Auto-close when complete
    if (state.isComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pop();
        }
      });
    }

    return PopScope(
      canPop: false, // Prevent back button dismissal
      child: Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    FluentIcons.database_arrow_right_24_regular,
                    size: 28,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Database Update',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'One-time migration required',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Error message if any
              if (state.error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        FluentIcons.error_circle_24_regular,
                        color: theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          state.error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: ElevatedButton(
                    onPressed: () {
                      ref.read(dataMigrationProvider.notifier).runMigrations();
                    },
                    child: const Text('Retry'),
                  ),
                ),
              ] else ...[
                // Current step
                Text(
                  state.currentStep.isEmpty
                      ? 'Preparing...'
                      : state.currentStep,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),

                // Progress message
                Text(
                  state.progressMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 16),

                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.totalProgress > 0 ? state.progressPercent : null,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Percentage
                if (state.totalProgress > 0)
                  Text(
                    '${(state.progressPercent * 100).toInt()}%',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
              ],
              const SizedBox(height: 16),

              // Info text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      FluentIcons.info_24_regular,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This process ensures Translation Memory works correctly. '
                        'Please do not close the application.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
