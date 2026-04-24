import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';

class BulkActionButtons extends ConsumerWidget {
  const BulkActionButtons({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targetLang = ref.watch(bulkTargetLanguageProvider).asData?.value;
    final bulkState = ref.watch(bulkOperationsProvider);
    final scopeAsync = ref.watch(visibleProjectsForBulkProvider);
    final scope = scopeAsync.asData?.value;

    final isRunning =
        bulkState.operationType != null && !bulkState.isComplete;
    final hasMatching = (scope?.matching.isNotEmpty ?? false);
    final canAct = targetLang != null && !isRunning && hasMatching;

    String? disabledTooltip;
    if (targetLang == null) {
      disabledTooltip = 'Select a target language';
    } else if (isRunning) {
      disabledTooltip = 'An operation is already running';
    } else if (!hasMatching) {
      disabledTooltip = 'No visible projects match';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BulkButton(
            icon: Icons.translate,
            label: 'Translate all',
            enabled: canAct,
            tooltip: disabledTooltip,
            onPressed: () => _start(context, ref, BulkOperationType.translate),
          ),
          const SizedBox(height: 8),
          _BulkButton(
            icon: Icons.refresh,
            label: 'Rescan reviews',
            enabled: canAct,
            tooltip: disabledTooltip,
            onPressed: () => _start(context, ref, BulkOperationType.rescan),
          ),
          const SizedBox(height: 8),
          _BulkButton(
            icon: Icons.verified,
            label: 'Force validate reviews',
            enabled: canAct,
            tooltip: disabledTooltip,
            danger: true,
            onPressed: () => _confirmThenStart(context, ref),
          ),
          const SizedBox(height: 8),
          _BulkButton(
            icon: Icons.inventory_2,
            label: 'Generate pack',
            enabled: canAct,
            tooltip: disabledTooltip,
            onPressed: () =>
                _start(context, ref, BulkOperationType.generatePack),
          ),
        ],
      ),
    );
  }

  void _start(BuildContext context, WidgetRef ref, BulkOperationType type) {
    final targetLang = ref.read(bulkTargetLanguageProvider).asData?.value;
    final scope = ref.read(visibleProjectsForBulkProvider).asData?.value;
    if (targetLang == null || scope == null) return;
    final matching = scope.matching;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const BulkOperationProgressDialog(),
    );
    ref.read(bulkOperationsProvider.notifier).run(
      type: type,
      targetLanguageCode: targetLang,
      projects: matching,
    );
  }

  Future<void> _confirmThenStart(BuildContext context, WidgetRef ref) async {
    final scope = ref.read(visibleProjectsForBulkProvider).asData?.value;
    final targetLang = ref.read(bulkTargetLanguageProvider).asData?.value;
    if (scope == null || targetLang == null) return;
    final matching = scope.matching;

    var units = 0;
    for (final p in matching) {
      final l = p.languages.firstWhere(
        (l) => l.language?.code == targetLang,
        orElse: () => throw StateError('unreachable'),
      );
      units += l.needsReviewUnits;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force validate reviews?'),
        content: Text(
          'This will mark $units units across ${matching.length} projects '
          'as validated for $targetLang, clearing all review flags. '
          'This cannot be undone from here. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Force validate'),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      _start(context, ref, BulkOperationType.forceValidate);
    }
  }
}

class _BulkButton extends StatelessWidget {
  const _BulkButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onPressed,
    this.tooltip,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final String? tooltip;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final button = FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon),
      label: Text(label),
      style: danger
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
    );
    if (!enabled && tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
