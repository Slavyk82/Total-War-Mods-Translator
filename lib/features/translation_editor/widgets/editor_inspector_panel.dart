import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_editor/providers/editor_inspector_width_notifier.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/utils/validation_issues_parser.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart' as batch;
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Callback fired when the user commits a target text edit (on focus loss).
typedef OnInspectorSave = void Function(String unitId, String text);

/// Callback fired when the user takes an action on a validation issue from
/// the inspector panel (Accept / Reject / Edit).
typedef OnInspectorIssueAction = void Function(batch.ValidationIssue issue);

/// Right inspector panel of the translation editor.
///
/// Width is user-resizable via the drag handle on the left edge, backed by
/// [editorInspectorWidthProvider] and clamped to `[minWidth, maxWidth]`.
///
/// Three render branches based on `editorSelectionProvider.selectedCount`:
/// - 0 -> empty placeholder.
/// - 1 -> full inspector (key + Source + Target), responsive layout with
///   equal-sized source/target fields that scroll internally when needed.
/// - N>1 -> multi-select header with batch hints.
class EditorInspectorPanel extends ConsumerStatefulWidget {
  final String projectId;
  final String languageId;
  final OnInspectorSave onSave;
  final OnInspectorIssueAction? onAcceptIssue;
  final OnInspectorIssueAction? onRejectIssue;
  final OnInspectorIssueAction? onEditIssue;

  const EditorInspectorPanel({
    super.key,
    required this.projectId,
    required this.languageId,
    required this.onSave,
    this.onAcceptIssue,
    this.onRejectIssue,
    this.onEditIssue,
  });

  @override
  ConsumerState<EditorInspectorPanel> createState() =>
      _EditorInspectorPanelState();
}

class _EditorInspectorPanelState extends ConsumerState<EditorInspectorPanel> {
  final _targetController = TextEditingController();
  String? _boundUnitId;

  @override
  void initState() {
    super.initState();
    // Listen for selection changes and resync the target controller out-of-band
    // (i.e. NOT during build). Both listeners converge on `_rebindIfNeeded`,
    // which is a no-op when the bound unit is already up to date.
    ref.listenManual<EditorSelectionState>(
      editorSelectionProvider,
      (_, _) => _rebindIfNeeded(),
      fireImmediately: true,
    );
    ref.listenManual<AsyncValue<List<TranslationRow>>>(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
      (_, _) => _rebindIfNeeded(),
      fireImmediately: true,
    );
  }

  @override
  void dispose() {
    _targetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final selection = ref.watch(editorSelectionProvider);
    final rowsAsync = ref.watch(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final rows = rowsAsync.value ?? const <TranslationRow>[];

    Widget body;
    if (selection.selectedCount == 0 || rows.isEmpty) {
      body = _EmptyState(tokens: tokens);
    } else if (selection.selectedCount > 1) {
      body = _MultiSelectHeader(
        count: selection.selectedCount,
        tokens: tokens,
      );
    } else {
      final selectedId = selection.selectedUnitIds.first;
      final idx = rows.indexWhere((r) => r.id == selectedId);
      if (idx < 0) {
        body = _EmptyState(tokens: tokens);
      } else {
        final row = rows[idx];
        body = _SingleSelectionBody(
          row: row,
          index: idx + 1,
          total: rows.length,
          controller: _targetController,
          onSave: (text) => widget.onSave(row.id, text),
          onAcceptIssue: widget.onAcceptIssue,
          onRejectIssue: widget.onRejectIssue,
          onEditIssue: widget.onEditIssue,
          tokens: tokens,
          projectId: widget.projectId,
          languageId: widget.languageId,
        );
      }
    }

    final width = ref.watch(editorInspectorWidthProvider);
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: tokens.panel,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ResizeHandle(
            tokens: tokens,
            onDrag: (dx) {
              // Dragging the handle left (negative dx) widens the panel; the
              // notifier clamps within [minWidth, maxWidth].
              final notifier =
                  ref.read(editorInspectorWidthProvider.notifier);
              notifier.setWidth(ref.read(editorInspectorWidthProvider) - dx);
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: body,
            ),
          ),
        ],
      ),
    );
  }

  /// Sync the target controller text with the currently selected row.
  ///
  /// Before rebinding to a new unit, fire `onSave` for the *previous* unit
  /// whenever the controller holds text that differs from the previously
  /// bound row's persisted translation. This prevents silent data loss when
  /// the user types then switches selection without blurring the field.
  void _rebindIfNeeded() {
    final selection = ref.read(editorSelectionProvider);
    final rowsAsync = ref.read(
      filteredTranslationRowsProvider(widget.projectId, widget.languageId),
    );
    final rows = rowsAsync.value;

    if (selection.selectedCount != 1) {
      // Multi/zero select: flush any dirty text for the previously bound unit
      // before we drop the binding.
      _flushDirtyIfNeeded(rows);
      _boundUnitId = null;
      return;
    }

    if (rows == null) return;
    final selectedId = selection.selectedUnitIds.first;
    final idx = rows.indexWhere((r) => r.id == selectedId);
    if (idx < 0) return;
    final row = rows[idx];

    if (_boundUnitId != row.id) {
      _flushDirtyIfNeeded(rows);
      _boundUnitId = row.id;
      _targetController.text = row.translatedText ?? '';
    }
  }

  /// Fire `onSave(previousId, dirtyText)` if the controller holds text that
  /// differs from the previously bound row's persisted translation.
  void _flushDirtyIfNeeded(List<TranslationRow>? rows) {
    final previousId = _boundUnitId;
    if (previousId == null) return;
    if (rows == null) return;
    final prevIdx = rows.indexWhere((r) => r.id == previousId);
    if (prevIdx < 0) return;
    final previousPersisted = rows[prevIdx].translatedText ?? '';
    final currentText = _targetController.text;
    if (currentText != previousPersisted) {
      widget.onSave(previousId, currentText);
    }
  }
}

class _EmptyState extends StatelessWidget {
  final TwmtThemeTokens tokens;
  const _EmptyState({required this.tokens});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.info_24_regular,
              size: 48,
              color: tokens.textFaint,
            ),
            const SizedBox(height: 16),
            Text(
              'Select a unit to view details',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMid, fontSize: 13),
            ),
          ],
        ),
      );
}

class _MultiSelectHeader extends StatelessWidget {
  final int count;
  final TwmtThemeTokens tokens;
  const _MultiSelectHeader({required this.count, required this.tokens});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count units selected',
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayStyle,
              fontSize: 16,
              color: tokens.accent,
            ),
          ),
        ],
      );
}

class _SingleSelectionBody extends ConsumerWidget {
  final TranslationRow row;
  final int index;
  final int total;
  final TextEditingController controller;
  final void Function(String) onSave;
  final OnInspectorIssueAction? onAcceptIssue;
  final OnInspectorIssueAction? onRejectIssue;
  final OnInspectorIssueAction? onEditIssue;
  final TwmtThemeTokens tokens;
  final String projectId;
  final String languageId;

  const _SingleSelectionBody({
    required this.row,
    required this.index,
    required this.total,
    required this.controller,
    required this.onSave,
    required this.onAcceptIssue,
    required this.onRejectIssue,
    required this.onEditIssue,
    required this.tokens,
    required this.projectId,
    required this.languageId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(currentProjectProvider(projectId)).value;
    final language = ref.watch(currentLanguageProvider(languageId)).value;
    final sourceCode = project?.sourceLanguageCode ?? 'en';
    final targetCode = language?.code ?? 'fr';

    // Only expose the Validation Issues section when the row is explicitly
    // flagged for review and still carries a persisted issue payload. A
    // row that got fixed but still sits in needsReview without issues won't
    // render the section (defensive: parseValidationIssues returns [] for
    // null / blank).
    final showValidationSection =
        row.status == TranslationVersionStatus.needsReview &&
            row.version.validationIssues != null;
    final parsed = showValidationSection
        ? parseValidationIssues(row.version.validationIssues)
        : const <ParsedValidationIssue>[];
    final hasIssues = parsed.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(index: index, total: total, tokens: tokens),
        const SizedBox(height: 10),
        if (hasIssues) ...[
          _ValidationIssuesSection(
            row: row,
            issues: parsed,
            onAccept: onAcceptIssue,
            onReject: onRejectIssue,
            onEdit: onEditIssue,
            tokens: tokens,
          ),
          const SizedBox(height: 14),
        ],
        _KeyChip(
          text: '${row.sourceLocFile ?? ''} / ${row.key}',
          tokens: tokens,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _SourceBlock(
            text: row.sourceText,
            lang: sourceCode,
            tokens: tokens,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _TargetBlock(
            controller: controller,
            lang: targetCode,
            onSave: onSave,
            tokens: tokens,
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  final int index;
  final int total;
  final TwmtThemeTokens tokens;
  const _Header({
    required this.index,
    required this.total,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Unit',
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayStyle,
              fontSize: 14,
              color: tokens.accent,
            ),
          ),
          Text(
            '$index / $total',
            style: tokens.fontMono.copyWith(
              fontSize: 10.5,
              color: tokens.textFaint,
            ),
          ),
        ],
      );
}

class _KeyChip extends StatelessWidget {
  final String text;
  final TwmtThemeTokens tokens;
  const _KeyChip({required this.text, required this.tokens});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.panel2,
          border: Border.all(color: tokens.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: tokens.fontMono.copyWith(
            fontSize: 11,
            color: tokens.textMid,
          ),
        ),
      );
}

class _SourceBlock extends StatelessWidget {
  final String text;
  final String lang;
  final TwmtThemeTokens tokens;
  const _SourceBlock({
    required this.text,
    required this.lang,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(text: 'Source · $lang', tokens: tokens),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 13,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: tokens.panel2,
                border: Border.all(color: tokens.border),
                borderRadius: BorderRadius.circular(4),
              ),
              child: SingleChildScrollView(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.textMid,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

class _TargetBlock extends StatelessWidget {
  final TextEditingController controller;
  final String lang;
  final void Function(String) onSave;
  final TwmtThemeTokens tokens;
  const _TargetBlock({
    required this.controller,
    required this.lang,
    required this.onSave,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label(
            text: 'Target · $lang — editing',
            tokens: tokens,
            withBullet: true,
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Focus(
              onFocusChange: (hasFocus) {
                // Commit the edit when the field loses focus.
                if (!hasFocus) onSave(controller.text);
              },
              child: TextField(
                key: const Key('editor-inspector-target-field'),
                controller: controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontSize: 13.5,
                  color: tokens.text,
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: tokens.accentBg,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: tokens.accent),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(color: tokens.accent, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

/// Vertical drag strip that sits on the left edge of the inspector panel.
///
/// Keeps a generous 6px hit-target but only paints a visible grip line on
/// hover or while dragging, so the resting state stays quiet. The horizontal
/// drag delta is forwarded to the parent which updates the width provider.
class _ResizeHandle extends StatefulWidget {
  final TwmtThemeTokens tokens;
  final void Function(double dx) onDrag;

  const _ResizeHandle({required this.tokens, required this.onDrag});

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(
            child: Container(
              width: 2,
              color: active ? widget.tokens.accent : Colors.transparent,
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  final TwmtThemeTokens tokens;
  final bool withBullet;
  const _Label({
    required this.text,
    required this.tokens,
    this.withBullet = false,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (withBullet) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            text.toUpperCase(),
            style: tokens.fontMono.copyWith(
              fontSize: 9.5,
              color: tokens.textFaint,
              letterSpacing: 1.5,
            ),
          ),
        ],
      );
}

/// Validation issues block shown for `needsReview` rows.
///
/// Lists every parsed issue with an icon/color derived from severity, then
/// a row of Accept / Reject / Edit action buttons. Each action fires with a
/// [batch.ValidationIssue] built from the row — severity is bucketed via
/// the shared `bucketSeverity` helper (critical folds into error, matching
/// the filter pill logic used by `grid_data_providers`).
class _ValidationIssuesSection extends StatelessWidget {
  final TranslationRow row;
  final List<ParsedValidationIssue> issues;
  final OnInspectorIssueAction? onAccept;
  final OnInspectorIssueAction? onReject;
  final OnInspectorIssueAction? onEdit;
  final TwmtThemeTokens tokens;

  const _ValidationIssuesSection({
    required this.row,
    required this.issues,
    required this.onAccept,
    required this.onReject,
    required this.onEdit,
    required this.tokens,
  });

  batch.ValidationIssue _toBatch(ParsedValidationIssue p) {
    // Fold `critical` into `error` via the shared `bucketSeverity` helper
    // so the editor filter pills and the inspector agree on which severity
    // surfaces where.
    return batch.ValidationIssue(
      unitKey: row.key,
      unitId: row.unit.id,
      versionId: row.version.id,
      severity: bucketSeverity(p.severity),
      issueType: p.type,
      description: p.description,
      sourceText: row.sourceText,
      translatedText: row.translatedText ?? '',
    );
  }

  @override
  Widget build(BuildContext context) {
    // The bulk actions target the version, not individual issues — we pass
    // the first parsed issue to the callback so the mixin has the
    // version+unit ids it needs. The action is idempotent regardless of which
    // issue we hand in.
    final primary = issues.first;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.panel2,
        border: Border.all(color: tokens.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'VALIDATION ISSUES',
            style: tokens.fontMono.copyWith(
              fontSize: 9.5,
              color: tokens.textFaint,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          for (final issue in issues) ...[
            _IssueRow(issue: issue, tokens: tokens),
            const SizedBox(height: 4),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _IssueActionButton(
                  label: 'Accept',
                  icon: FluentIcons.checkmark_24_regular,
                  color: tokens.accent,
                  onTap: onAccept == null
                      ? null
                      : () => onAccept!(_toBatch(primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IssueActionButton(
                  label: 'Reject',
                  icon: FluentIcons.dismiss_24_regular,
                  color: tokens.err,
                  onTap: onReject == null
                      ? null
                      : () => onReject!(_toBatch(primary)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _IssueActionButton(
                  label: 'Edit',
                  icon: FluentIcons.edit_24_regular,
                  color: tokens.accent,
                  onTap:
                      onEdit == null ? null : () => onEdit!(_toBatch(primary)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IssueRow extends StatelessWidget {
  final ParsedValidationIssue issue;
  final TwmtThemeTokens tokens;
  const _IssueRow({required this.issue, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final isError =
        bucketSeverity(issue.severity) == batch.ValidationSeverity.error;
    final color = isError ? tokens.err : tokens.warn;
    final icon = isError
        ? FluentIcons.error_circle_24_filled
        : FluentIcons.warning_24_filled;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            issue.description,
            style: TextStyle(fontSize: 12, color: tokens.textMid),
          ),
        ),
      ],
    );
  }
}

class _IssueActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _IssueActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: enabled ? 0.10 : 0.04),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
