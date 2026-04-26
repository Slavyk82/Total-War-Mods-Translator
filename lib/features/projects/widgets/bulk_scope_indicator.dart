import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';

class BulkScopeIndicator extends ConsumerWidget {
  const BulkScopeIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeAsync = ref.watch(visibleProjectsForBulkProvider);
    return scopeAsync.when(
      data: (scope) => Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          t.projects.bulk.scopeMessage(
            visible: scope.visible.length,
            matching: scope.matching.length,
          ),
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
