import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';

class BulkInfoCard extends ConsumerWidget {
  const BulkInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(bulkInfoCardDismissedProvider).asData?.value ?? false;
    if (dismissed) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Bulk actions are designed for projects already partially '
              'translated. The bulk of the work should be done project by '
              'project in the editor — bulk is here to finish up or harmonise.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            iconSize: 16,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            onPressed: () =>
                ref.read(bulkInfoCardDismissedProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }
}
