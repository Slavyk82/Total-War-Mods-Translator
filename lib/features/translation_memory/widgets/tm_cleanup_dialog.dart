import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../providers/tm_providers.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../widgets/fluent/fluent_progress_indicator.dart';

/// Dialog for cleaning up low-quality TM entries
class TmCleanupDialog extends ConsumerStatefulWidget {
  const TmCleanupDialog({super.key});

  @override
  ConsumerState<TmCleanupDialog> createState() => _TmCleanupDialogState();
}

class _TmCleanupDialogState extends ConsumerState<TmCleanupDialog> {
  int _unusedDays = 365; // Default to 365 days for unused entry cleanup

  @override
  Widget build(BuildContext context) {
    final cleanupState = ref.watch(tmCleanupStateProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            FluentIcons.broom_24_regular,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          const Text('Cleanup Translation Memory'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Remove unused entries to optimize your translation memory.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),

            const SizedBox(height: 24),

            // Unused days
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Delete if unused for (days)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  _unusedDays == 0 ? 'Disabled' : '$_unusedDays',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: _unusedDays == 0
                            ? Theme.of(context).colorScheme.secondary
                            : Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            Slider(
              value: _unusedDays.toDouble(),
              min: 0,
              max: 730,
              divisions: 73, // 0, 10, 20, ... 730
              onChanged: (value) {
                setState(() {
                  _unusedDays = value.toInt();
                });
              },
            ),
            if (_unusedDays == 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Age filter disabled - no entries will be deleted',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ),

            const SizedBox(height: 24),

            // Result
            cleanupState.when(
              data: (deletedCount) {
                if (deletedCount != null) {
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          FluentIcons.checkmark_circle_24_filled,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Deleted $deletedCount entries',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const FluentProgressBar(),
              error: (error, stack) => Text(
                error.toString(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FluentTextButton(
          onPressed: cleanupState.isLoading
              ? null
              : () {
                  ref.read(tmCleanupStateProvider.notifier).reset();
                  Navigator.of(context).pop();
                },
          child: const Text('Cancel'),
        ),
        FluentButton(
          onPressed: cleanupState.isLoading
              ? null
              : () async {
                  await ref.read(tmCleanupStateProvider.notifier).cleanup(
                        unusedDays: _unusedDays,
                      );
                },
          icon: const Icon(FluentIcons.broom_24_regular),
          child: const Text('Cleanup'),
        ),
      ],
    );
  }
}
