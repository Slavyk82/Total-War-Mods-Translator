import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

enum _BulkButtonVariant { primary, regular, danger }

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
            variant: _BulkButtonVariant.primary,
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
            variant: _BulkButtonVariant.danger,
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
    this.variant = _BulkButtonVariant.regular,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final String? tooltip;
  final _BulkButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final Color bg;
    final Color fg;
    final Color borderColor;
    switch (variant) {
      case _BulkButtonVariant.primary:
        bg = enabled ? tokens.accent : tokens.accent.withValues(alpha: 0.4);
        fg = enabled ? tokens.accentFg : tokens.accentFg.withValues(alpha: 0.6);
        borderColor = bg;
      case _BulkButtonVariant.danger:
        bg = enabled ? tokens.errBg : Colors.transparent;
        fg = enabled ? tokens.err : tokens.textFaint;
        borderColor = enabled ? tokens.err : tokens.border;
      case _BulkButtonVariant.regular:
        bg = enabled ? tokens.panel2 : Colors.transparent;
        fg = enabled ? tokens.text : tokens.textFaint;
        borderColor = tokens.border;
    }

    final button = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onPressed : null,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: fg,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!enabled && tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
