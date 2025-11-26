import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/widgets/fluent/fluent_widgets.dart';

/// Builds the preparation view shown while batch is being prepared
Widget buildPreparationView(
  BuildContext context, {
  String? errorMessage,
  required VoidCallback onClose,
}) {
  final theme = Theme.of(context);

  return Center(
    child: Container(
      constraints: const BoxConstraints(maxWidth: 600),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: FluentProgressRing(
              strokeWidth: 6,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            'Preparing Translation',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Creating batch and gathering context...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    FluentIcons.error_circle_24_regular,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      errorMessage,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FluentButton(
              onPressed: onClose,
              child: const Text('Close'),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Builds the header with batch ID and icon
Widget buildProgressHeader(
  BuildContext context, {
  required String batchId,
}) {
  final theme = Theme.of(context);

  return Row(
    children: [
      Icon(
        FluentIcons.translate_24_regular,
        size: 48,
        color: theme.colorScheme.primary,
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mass Translation',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Batch ID: ${batchId.length > 8 ? '${batchId.substring(0, 8)}...' : batchId}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Builds the main progress bar section
Widget buildProgressSection(
  BuildContext context, {
  required TranslationProgress? progress,
  required bool isPaused,
}) {
  final percentage = progress?.progressPercentage ?? 0.0;
  final theme = Theme.of(context);

  return Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Progress',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              '${(percentage * 100).toStringAsFixed(1)}%',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FluentProgressBar(
          value: percentage,
          height: 12,
          color:
              isPaused ? Colors.orange.shade700 : theme.colorScheme.primary,
          backgroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        const SizedBox(height: 12),
        Text(
          '${progress?.processedUnits ?? 0} / ${progress?.totalUnits ?? 0} units',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    ),
  );
}

/// Builds a single stat card
Widget buildStatCard(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  final theme = Theme.of(context);

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      border: Border.all(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.15),
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        Icon(icon, size: 32, color: color),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    ),
  );
}

/// Builds the stats row (success, failed, skipped)
Widget buildStatsSection(
  BuildContext context, {
  required TranslationProgress? progress,
}) {
  final theme = Theme.of(context);

  return Row(
    children: [
      Expanded(
        child: buildStatCard(
          context,
          icon: FluentIcons.checkmark_circle_24_regular,
          label: 'Success',
          value: progress?.successfulUnits.toString() ?? '0',
          color: Colors.green.shade700,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: buildStatCard(
          context,
          icon: FluentIcons.dismiss_circle_24_regular,
          label: 'Failed',
          value: progress?.failedUnits.toString() ?? '0',
          color: theme.colorScheme.error,
        ),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: buildStatCard(
          context,
          icon: FluentIcons.fast_forward_24_regular,
          label: 'Skipped',
          value: progress?.skippedUnits.toString() ?? '0',
          color: Colors.blue.shade700,
        ),
      ),
    ],
  );
}

/// Builds the error section
Widget buildErrorSection(
  BuildContext context, {
  required String errorMessage,
}) {
  final theme = Theme.of(context);
  final errorColor = theme.colorScheme.error;

  return Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: errorColor.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: errorColor.withValues(alpha: 0.3)),
    ),
    child: Row(
      children: [
        Icon(
          FluentIcons.error_circle_24_regular,
          size: 32,
          color: errorColor,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Error',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: errorColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                errorMessage,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: errorColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
