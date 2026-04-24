import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';

class BulkOperationProgressDialog extends ConsumerWidget {
  const BulkOperationProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(bulkOperationsProvider);
    final title = _titleFor(s.operationType);
    final subtitle = 'Target language: ${s.targetLanguageCode ?? '—'}';

    return AlertDialog(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title),
          Text(subtitle, style: const TextStyle(fontSize: 12)),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 420,
        child: Column(
          children: [
            LinearProgressIndicator(
              value: s.projectIds.isEmpty
                  ? 0
                  : s.currentIndex / s.projectIds.length,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${s.currentIndex}/${s.projectIds.length} projects'),
              ),
            ),
            const SizedBox(height: 12),
            if (!s.isComplete) _CurrentProjectBlock(state: s),
            const SizedBox(height: 12),
            Expanded(child: _TimelineList(state: s)),
          ],
        ),
      ),
      actions: _footerActions(context, ref, s),
    );
  }

  String _titleFor(BulkOperationType? type) {
    switch (type) {
      case BulkOperationType.translate:
        return 'Translating projects';
      case BulkOperationType.rescan:
        return 'Rescanning reviews';
      case BulkOperationType.forceValidate:
        return 'Force-validating reviews';
      case BulkOperationType.generatePack:
        return 'Generating packs';
      case null:
        return 'Bulk operation';
    }
  }

  List<Widget> _footerActions(
    BuildContext context,
    WidgetRef ref,
    BulkOperationState s,
  ) {
    if (s.isComplete) {
      final failed = s.countByStatus(ProjectResultStatus.failed);
      return [
        Text(
          '${s.countByStatus(ProjectResultStatus.succeeded)} succeeded · '
          '${s.countByStatus(ProjectResultStatus.skipped)} skipped · '
          '$failed failed',
        ),
        if (failed > 0)
          TextButton(
            onPressed: () => _retryFailed(context, ref, s),
            child: const Text('Retry failed'),
          ),
        FilledButton(
          onPressed: () {
            ref.read(bulkOperationsProvider.notifier).reset();
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
      ];
    }
    if (s.isCancelled) {
      return [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 8),
              Text('Cancelling…'),
            ],
          ),
        ),
      ];
    }
    return [
      OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        onPressed: () => _confirmCancel(context, ref),
        child: const Text('Cancel'),
      ),
    ];
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop the current operation?'),
        content: const Text(
            'Projects already processed will keep their changes.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep running'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(bulkOperationsProvider.notifier).cancel();
    }
  }

  void _retryFailed(
    BuildContext context,
    WidgetRef ref,
    BulkOperationState s,
  ) {
    final scope = ref.read(visibleProjectsForBulkProvider).asData?.value;
    if (scope == null) return;
    final failedIds = s.failedProjectIds.toSet();
    final failedProjects =
        scope.matching.where((p) => failedIds.contains(p.project.id)).toList();
    final type = s.operationType;
    final targetLang = s.targetLanguageCode;
    if (type == null || targetLang == null) return;
    ref.read(bulkOperationsProvider.notifier).reset();
    ref.read(bulkOperationsProvider.notifier).run(
      type: type,
      targetLanguageCode: targetLang,
      projects: failedProjects,
    );
  }
}

class _CurrentProjectBlock extends StatelessWidget {
  const _CurrentProjectBlock({required this.state});
  final BulkOperationState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          state.currentProjectName ?? '',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(state.currentStep ?? ''),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: state.currentProjectProgress < 0
              ? null
              : state.currentProjectProgress,
        ),
      ],
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.state});
  final BulkOperationState state;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: state.projectIds.length,
      itemBuilder: (ctx, i) {
        final id = state.projectIds[i];
        final outcome = state.results[id];
        return ListTile(
          dense: true,
          leading: _statusIcon(outcome?.status ?? ProjectResultStatus.pending),
          title: Text(state.projectNames[id] ?? id),
          trailing: outcome?.message != null
              ? Text(outcome!.message!, style: const TextStyle(fontSize: 11))
              : null,
          enabled: state.isComplete,
        );
      },
    );
  }

  Widget _statusIcon(ProjectResultStatus s) {
    switch (s) {
      case ProjectResultStatus.pending:
        return const Icon(Icons.circle_outlined, size: 16);
      case ProjectResultStatus.inProgress:
        return const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case ProjectResultStatus.succeeded:
        return const Icon(Icons.check, color: Colors.green, size: 16);
      case ProjectResultStatus.skipped:
        return const Icon(Icons.remove, size: 16);
      case ProjectResultStatus.failed:
        return const Icon(Icons.close, color: Colors.red, size: 16);
      case ProjectResultStatus.cancelled:
        return const Icon(Icons.stop, size: 16);
    }
  }
}
