import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

/// Dialog showing progress of clear translations operation
class ClearProgressDialog extends StatelessWidget {
  final int processed;
  final int total;
  final String phase;

  const ClearProgressDialog({
    super.key,
    required this.processed,
    required this.total,
    required this.phase,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total > 0 ? processed / total : 0.0;
    final percentage = (progress * 100).toStringAsFixed(0);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(FluentIcons.delete_24_regular, size: 24),
          const SizedBox(width: 12),
          const Text('Clearing Translations'),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              phase,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$processed / $total',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  '$percentage%',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
