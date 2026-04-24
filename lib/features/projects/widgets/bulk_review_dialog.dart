import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/projects/providers/bulk_operation_state.dart';
import 'package:twmt/features/projects/providers/bulk_operations_notifier.dart';
import 'package:twmt/features/projects/providers/bulk_review_rows_provider.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/providers/visible_projects_for_bulk_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_operation_progress_dialog.dart';
import 'package:twmt/features/translation_editor/providers/llm_model_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/dialogs/token_dialog.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

/// Per-row action currently running. Used to show spinners and disable
/// buttons without pulling in a full state object.
enum _RowAction { none, validating, retranslating }

class BulkReviewDialog extends ConsumerStatefulWidget {
  const BulkReviewDialog({super.key});

  @override
  ConsumerState<BulkReviewDialog> createState() => _BulkReviewDialogState();
}

class _BulkReviewDialogState extends ConsumerState<BulkReviewDialog> {
  final _inFlight = <String, _RowAction>{}; // keyed by versionId
  bool _busy = false; // set during "Validate all" / pre-launch of retranslate all

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final rowsAsync = ref.watch(bulkReviewRowsProvider);
    final targetCode =
        ref.watch(bulkTargetLanguageProvider).asData?.value ?? '—';

    final rows = rowsAsync.asData?.value ?? const <BulkReviewRow>[];
    final projectCount = rows.map((r) => r.projectId).toSet().length;
    final subtitle =
        'Target: $targetCode · ${rows.length} units across $projectCount projects';

    final hasRows = rows.isNotEmpty;
    final canAct = hasRows && !_busy;

    return TokenDialog(
      icon: FluentIcons.task_list_square_rtl_24_regular,
      iconColor: tokens.accent,
      title: 'Review flagged translations',
      subtitle: subtitle,
      width: 760,
      body: SizedBox(
        height: 460,
        child: rowsAsync.when(
          data: (list) => list.isEmpty
              ? _EmptyState(tokens: tokens)
              : _RowsList(
                  rows: list,
                  inFlight: _inFlight,
                  onValidate: _validateOne,
                  onRetranslate: _retranslateOne,
                ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Failed to load review queue: $e',
              style:
                  tokens.fontBody.copyWith(color: tokens.err, fontSize: 12.5),
            ),
          ),
        ),
      ),
      leadingActions: [
        if (_busy)
          _InlineSpinner(tokens: tokens, label: 'Working…')
        else
          SmallTextButton(
            label: 'Refresh',
            icon: FluentIcons.arrow_clockwise_24_regular,
            onTap: () => ref.invalidate(bulkReviewRowsProvider),
          ),
      ],
      actions: [
        SmallTextButton(
          label: 'Close',
          onTap: () => Navigator.of(context).pop(),
        ),
        SmallTextButton(
          label: 'Validate all',
          icon: FluentIcons.checkmark_circle_24_regular,
          onTap: canAct ? () => _validateAll(rows) : null,
        ),
        SmallTextButton(
          label: 'Force retranslate all',
          icon: FluentIcons.arrow_clockwise_24_regular,
          filled: true,
          onTap: canAct ? () => _retranslateAll(rows) : null,
        ),
      ],
    );
  }

  Future<void> _validateOne(BulkReviewRow row) async {
    if (_inFlight[row.versionId] != _RowAction.none &&
        _inFlight.containsKey(row.versionId)) {
      return;
    }
    setState(() => _inFlight[row.versionId] = _RowAction.validating);
    final repo = ref.read(translationVersionRepositoryProvider);
    final result = await repo.acceptBatch([row.versionId]);
    if (!mounted) return;
    setState(() => _inFlight.remove(row.versionId));
    if (result.isErr) {
      _showError('Failed to validate: ${result.unwrapErr()}');
      return;
    }
    ref.invalidate(bulkReviewRowsProvider);
    ref.invalidate(projectsWithDetailsProvider);
  }

  Future<void> _retranslateOne(BulkReviewRow row) async {
    if (_inFlight.containsKey(row.versionId)) return;
    setState(() => _inFlight[row.versionId] = _RowAction.retranslating);
    try {
      final resolved = await _resolveProviderModel(ref);
      if (resolved == null) {
        if (!mounted) return;
        _showError('No LLM model selected');
        setState(() => _inFlight.remove(row.versionId));
        return;
      }
      final runner = ref.read(headlessBatchTranslationRunnerProvider);
      await runner.run(
        projectLanguageId: row.projectLanguageId,
        projectId: row.projectId,
        unitIds: [row.unitId],
        skipTM: true,
        providerId: resolved.providerId,
        modelId: resolved.modelId,
      );
      if (!mounted) return;
      ref.invalidate(bulkReviewRowsProvider);
      ref.invalidate(projectsWithDetailsProvider);
    } catch (e) {
      if (!mounted) return;
      _showError('Retranslate failed: $e');
    } finally {
      if (mounted) {
        setState(() => _inFlight.remove(row.versionId));
      }
    }
  }

  Future<void> _validateAll(List<BulkReviewRow> rows) async {
    if (rows.isEmpty) return;
    setState(() => _busy = true);
    final repo = ref.read(translationVersionRepositoryProvider);
    final ids = rows.map((r) => r.versionId).toList();
    final result = await repo.acceptBatch(ids);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isErr) {
      _showError('Failed to validate all: ${result.unwrapErr()}');
      return;
    }
    ref.invalidate(bulkReviewRowsProvider);
    ref.invalidate(projectsWithDetailsProvider);
  }

  void _retranslateAll(List<BulkReviewRow> rows) {
    if (rows.isEmpty) return;
    final targetCode = ref.read(bulkTargetLanguageProvider).asData?.value;
    final scope = ref.read(visibleProjectsForBulkProvider).asData?.value;
    if (targetCode == null || scope == null) return;

    // Only retranslate projects that actually have flagged units in the
    // current review list — otherwise the bulk loop would run against every
    // matching project and immediately skip most of them.
    final projectIdsWithRows = rows.map((r) => r.projectId).toSet();
    final projects = scope.matching
        .where((p) => projectIdsWithRows.contains(p.project.id))
        .toList();
    if (projects.isEmpty) return;

    // Stack the progress dialog on top of the review dialog. When it's
    // dismissed, the review provider has already invalidated via the
    // notifier's per-project `ref.invalidate(projectsWithDetailsProvider)`
    // so the list behind us refreshes to the new state.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const BulkOperationProgressDialog(),
    );
    ref.read(bulkOperationsProvider.notifier).run(
      type: BulkOperationType.translateReviews,
      targetLanguageCode: targetCode,
      projects: projects,
    );
  }

  void _showError(String message) {
    final tokens = context.tokens;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: tokens.errBg,
        content: Text(
          message,
          style: tokens.fontBody.copyWith(color: tokens.err, fontSize: 12.5),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Provider / model resolution helper (mirrors bulk_operations_handlers'
// private _resolveSelectedProvider). Kept tiny and private so the dialog
// doesn't take a dependency on a test-seam abstraction.
// ---------------------------------------------------------------------------

Future<({String providerId, String? modelId})?> _resolveProviderModel(
  WidgetRef ref,
) async {
  final selectedModelId = ref.read(selectedLlmModelProvider);
  if (selectedModelId != null) {
    final modelRepo = ref.read(llmProviderModelRepositoryProvider);
    final modelResult = await modelRepo.getById(selectedModelId);
    if (modelResult.isOk) {
      final model = modelResult.unwrap();
      return (
        providerId: 'provider_${model.providerCode}',
        modelId: model.modelId,
      );
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _RowsList extends StatelessWidget {
  const _RowsList({
    required this.rows,
    required this.inFlight,
    required this.onValidate,
    required this.onRetranslate,
  });
  final List<BulkReviewRow> rows;
  final Map<String, _RowAction> inFlight;
  final Future<void> Function(BulkReviewRow) onValidate;
  final Future<void> Function(BulkReviewRow) onRetranslate;

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
        padding: EdgeInsets.zero,
        itemCount: rows.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, thickness: 1, color: tokens.border),
        itemBuilder: (_, i) => _ReviewRowTile(
          row: rows[i],
          action: inFlight[rows[i].versionId] ?? _RowAction.none,
          onValidate: () => onValidate(rows[i]),
          onRetranslate: () => onRetranslate(rows[i]),
        ),
      ),
    );
  }
}

class _ReviewRowTile extends StatelessWidget {
  const _ReviewRowTile({
    required this.row,
    required this.action,
    required this.onValidate,
    required this.onRetranslate,
  });
  final BulkReviewRow row;
  final _RowAction action;
  final VoidCallback onValidate;
  final VoidCallback onRetranslate;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final busy = action != _RowAction.none;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.projectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.fontBody.copyWith(
                          fontSize: 11.5,
                          color: tokens.textDim,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '  ·  ',
                      style: tokens.fontBody
                          .copyWith(fontSize: 11.5, color: tokens.textFaint),
                    ),
                    Flexible(
                      child: Text(
                        row.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tokens.fontMono.copyWith(
                          fontSize: 11,
                          color: tokens.textFaint,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _TextBlock(
                  label: 'EN',
                  text: row.sourceText,
                  tokens: tokens,
                  color: tokens.text,
                ),
                const SizedBox(height: 4),
                _TextBlock(
                  label: 'Translation',
                  text: row.translatedText ?? '(empty)',
                  tokens: tokens,
                  color: row.translatedText == null
                      ? tokens.textFaint
                      : tokens.textMid,
                  italic: row.translatedText == null,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _RowActionButton(
            icon: FluentIcons.checkmark_circle_24_regular,
            tooltip: 'Validate (clear review flag)',
            color: tokens.ok,
            busy: action == _RowAction.validating,
            enabled: !busy,
            onTap: onValidate,
          ),
          const SizedBox(width: 4),
          _RowActionButton(
            icon: FluentIcons.arrow_clockwise_24_regular,
            tooltip: 'Force retranslate this unit',
            color: tokens.accent,
            busy: action == _RowAction.retranslating,
            enabled: !busy,
            onTap: onRetranslate,
          ),
        ],
      ),
    );
  }
}

class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.label,
    required this.text,
    required this.tokens,
    required this.color,
    this.italic = false,
  });
  final String label;
  final String text;
  final TwmtThemeTokens tokens;
  final Color color;
  final bool italic;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label.toUpperCase(),
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textFaint,
              letterSpacing: 0.6,
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: color,
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _RowActionButton extends StatelessWidget {
  const _RowActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.busy,
    required this.enabled,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool busy;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tint = enabled ? color : tokens.textFaint;
    final child = busy
        ? SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: color,
            ),
          )
        : Icon(icon, size: 18, color: tint);

    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: (enabled && !busy) ? onTap : null,
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.panel,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tokens});
  final TwmtThemeTokens tokens;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.checkmark_circle_24_regular,
            size: 40,
            color: tokens.ok,
          ),
          const SizedBox(height: 12),
          Text(
            'No flagged translations',
            style: tokens.fontDisplay.copyWith(
              fontSize: 15,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Every visible project is up to date for this language.',
            style: tokens.fontBody
                .copyWith(fontSize: 12, color: tokens.textDim),
          ),
        ],
      ),
    );
  }
}

class _InlineSpinner extends StatelessWidget {
  const _InlineSpinner({required this.tokens, required this.label});
  final TwmtThemeTokens tokens;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
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
          label,
          style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
        ),
      ],
    );
  }
}
