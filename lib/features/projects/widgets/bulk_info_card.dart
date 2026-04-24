import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_info_card_dismissed_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

class BulkInfoCard extends ConsumerWidget {
  const BulkInfoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dismissed = ref.watch(bulkInfoCardDismissedProvider).asData?.value ?? false;
    if (dismissed) return const SizedBox.shrink();

    final tokens = context.tokens;

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      decoration: BoxDecoration(
        color: tokens.warnBg,
        border: Border.all(color: tokens.warn.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(tokens.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: tokens.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Bulk actions are designed for projects already partially '
              'translated. The bulk of the work should be done project by '
              'project in the editor — bulk is here to finish up or harmonise.',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.text,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: tokens.textMid),
            iconSize: 16,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            tooltip: 'Hide',
            onPressed: () =>
                ref.read(bulkInfoCardDismissedProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }
}
