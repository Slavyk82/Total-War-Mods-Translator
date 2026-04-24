import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

class BulkOperationProgressDialog extends ConsumerWidget {
  const BulkOperationProgressDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final s = ref.watch(bulkOperationsProvider);
    final title = _titleFor(s.operationType);
    final subtitle = 'Target language: ${s.targetLanguageCode ?? '—'}';
    // `currentIndex` is 0-based and stays on the last processed project once
    // the loop exits, so it tops out at `n - 1` at completion. Snap to full
    // when the notifier signals `isComplete`, otherwise trust the index.
    final processedCount = s.isComplete ? s.projectIds.length : s.currentIndex;
    final overallProgress = s.projectIds.isEmpty
        ? 0.0
        : processedCount / s.projectIds.length;

    final (leadingActions, trailingActions) = _footerActions(context, ref, s);

    return TokenDialog(
      icon: _iconFor(s.operationType),
      iconColor: s.isComplete ? tokens.ok : tokens.accent,
      title: title,
      subtitle: subtitle,
      width: 560,
      leadingActions: leadingActions,
      actions: trailingActions,
      body: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _OverallProgress(
              progress: overallProgress,
              processedCount: processedCount,
              total: s.projectIds.length,
            ),
            const SizedBox(height: 12),
            if (!s.isComplete) _CurrentProjectBlock(state: s),
            if (!s.isComplete) const SizedBox(height: 12),
            Expanded(child: _TimelineList(state: s)),
          ],
        ),
      ),
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
      case BulkOperationType.translateReviews:
        return 'Retranslating flagged units';
      case null:
        return 'Bulk operation';
    }
  }

  IconData _iconFor(BulkOperationType? type) {
    switch (type) {
      case BulkOperationType.translate:
        return FluentIcons.translate_24_regular;
      case BulkOperationType.rescan:
        return FluentIcons.arrow_sync_24_regular;
      case BulkOperationType.forceValidate:
        return FluentIcons.shield_checkmark_24_regular;
      case BulkOperationType.generatePack:
        return FluentIcons.box_24_regular;
      case BulkOperationType.translateReviews:
        return FluentIcons.arrow_clockwise_24_regular;
      case null:
        return FluentIcons.play_circle_24_regular;
    }
  }

  (List<Widget> leading, List<Widget> trailing) _footerActions(
    BuildContext context,
    WidgetRef ref,
    BulkOperationState s,
  ) {
    final tokens = context.tokens;

    if (s.isComplete) {
      final failed = s.countByStatus(ProjectResultStatus.failed);
      final summary = Flexible(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            '${s.countByStatus(ProjectResultStatus.succeeded)} succeeded · '
            '${s.countByStatus(ProjectResultStatus.skipped)} skipped · '
            '$failed failed',
            overflow: TextOverflow.ellipsis,
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.textDim,
            ),
          ),
        ),
      );
      final trailing = <Widget>[
        if (failed > 0)
          SmallTextButton(
            label: 'Retry failed',
            icon: FluentIcons.arrow_clockwise_24_regular,
            onTap: () => _retryFailed(context, ref, s),
          ),
        SmallTextButton(
          label: 'Close',
          filled: true,
          onTap: () {
            ref.read(bulkOperationsProvider.notifier).reset();
            Navigator.of(context).pop();
          },
        ),
      ];
      return ([summary], trailing);
    }

    if (s.isCancelled) {
      final spinner = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.accent,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Cancelling…',
            style: tokens.fontBody
                .copyWith(fontSize: 12, color: tokens.textDim),
          ),
        ],
      );
      return ([spinner], <Widget>[]);
    }

    return (
      <Widget>[],
      <Widget>[
        SmallTextButton(
          label: 'Cancel',
          icon: FluentIcons.dismiss_24_regular,
          onTap: () => _confirmCancel(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const TokenConfirmDialog(
        icon: FluentIcons.warning_24_regular,
        title: 'Stop the current operation?',
        message: 'Projects already processed will keep their changes.',
        confirmLabel: 'Stop',
        cancelLabel: 'Keep running',
        destructive: true,
        confirmIcon: FluentIcons.stop_24_regular,
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

class _OverallProgress extends StatelessWidget {
  const _OverallProgress({
    required this.progress,
    required this.processedCount,
    required this.total,
  });
  final double progress;
  final int processedCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens.radiusSm),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: tokens.panel2,
            valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$processedCount / $total projects',
              style: tokens.fontBody
                  .copyWith(fontSize: 12, color: tokens.textDim),
            ),
            Text(
              '${(progress * 100).toStringAsFixed(0)}%',
              style: tokens.fontBody.copyWith(
                fontSize: 12,
                color: tokens.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CurrentProjectBlock extends StatelessWidget {
  const _CurrentProjectBlock({required this.state});
  final BulkOperationState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            state.currentProjectName ?? '—',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          if ((state.currentStep ?? '').isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              state.currentStep!,
              style: tokens.fontBody
                  .copyWith(fontSize: 12, color: tokens.textDim),
            ),
          ],
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens.radiusXs),
            child: LinearProgressIndicator(
              value: state.currentProjectProgress < 0
                  ? null
                  : state.currentProjectProgress,
              minHeight: 4,
              backgroundColor: tokens.border,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineList extends StatelessWidget {
  const _TimelineList({required this.state});
  final BulkOperationState state;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: state.projectIds.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, thickness: 1, color: tokens.border),
        itemBuilder: (ctx, i) {
          final id = state.projectIds[i];
          final outcome = state.results[id];
          final status = outcome?.status ?? ProjectResultStatus.pending;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                _StatusIcon(status: status),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    state.projectNames[id] ?? id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.fontBody.copyWith(
                      fontSize: 12.5,
                      color: status == ProjectResultStatus.pending
                          ? tokens.textDim
                          : tokens.text,
                    ),
                  ),
                ),
                if (outcome?.message != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      outcome!.message!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: tokens.fontBody.copyWith(
                        fontSize: 11,
                        color: _statusColor(tokens, status),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({required this.status});
  final ProjectResultStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    switch (status) {
      case ProjectResultStatus.pending:
        return Icon(
          FluentIcons.circle_24_regular,
          size: 16,
          color: tokens.textFaint,
        );
      case ProjectResultStatus.inProgress:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: tokens.accent,
          ),
        );
      case ProjectResultStatus.succeeded:
        return Icon(
          FluentIcons.checkmark_circle_24_filled,
          size: 16,
          color: tokens.ok,
        );
      case ProjectResultStatus.skipped:
        return Icon(
          FluentIcons.subtract_circle_24_regular,
          size: 16,
          color: tokens.textMid,
        );
      case ProjectResultStatus.failed:
        return Icon(
          FluentIcons.error_circle_24_filled,
          size: 16,
          color: tokens.err,
        );
      case ProjectResultStatus.cancelled:
        return Icon(
          FluentIcons.stop_24_filled,
          size: 16,
          color: tokens.warn,
        );
    }
  }
}

Color _statusColor(TwmtThemeTokens tokens, ProjectResultStatus status) {
  switch (status) {
    case ProjectResultStatus.failed:
      return tokens.err;
    case ProjectResultStatus.cancelled:
      return tokens.warn;
    case ProjectResultStatus.succeeded:
      return tokens.ok;
    case ProjectResultStatus.skipped:
    case ProjectResultStatus.pending:
    case ProjectResultStatus.inProgress:
      return tokens.textDim;
  }
}
