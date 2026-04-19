import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_editor/providers/validation_inspector_width_notifier.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Right-hand detail panel of the Validation Review screen.
///
/// Width is user-resizable via the drag handle on the left edge, backed by
/// [validationInspectorWidthProvider] and clamped to `[minWidth, maxWidth]`.
///
/// Four render branches, resolved in order:
/// - `selectedCount > 1` -> multi-select header (count + bulk hint).
/// - `currentIssue == null` -> empty placeholder.
/// - `isProcessing` (single-select only) -> centred spinner. Bulk operations
///   from the toolbar do not drive this branch — they leave the multi-select
///   header in place.
/// - otherwise -> full body (key chip + severity + source/translation blocks +
///   Edit/Accept/Reject action row).
class ValidationReviewInspectorPanel extends ConsumerWidget {
  final ValidationIssue? currentIssue;
  final int? currentIndex;
  final int total;
  final bool isProcessing;
  final int selectedCount;
  final VoidCallback onEdit;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const ValidationReviewInspectorPanel({
    super.key,
    required this.currentIssue,
    required this.currentIndex,
    required this.total,
    required this.isProcessing,
    required this.selectedCount,
    required this.onEdit,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final width = ref.watch(validationInspectorWidthProvider);

    final Widget body;
    if (selectedCount > 1) {
      body = _MultiSelectHeader(count: selectedCount, tokens: tokens);
    } else if (currentIssue == null) {
      body = _EmptyState(tokens: tokens);
    } else if (isProcessing) {
      body = const _ProcessingState();
    } else {
      body = _SingleIssueBody(
        issue: currentIssue!,
        index: currentIndex ?? 0,
        total: total,
        onEdit: onEdit,
        onAccept: onAccept,
        onReject: onReject,
        tokens: tokens,
      );
    }

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
              final notifier =
                  ref.read(validationInspectorWidthProvider.notifier);
              notifier
                  .setWidth(ref.read(validationInspectorWidthProvider) - dx);
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
              'Select an issue to view details',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textMid, fontSize: 13),
            ),
          ],
        ),
      );
}

/// Vertical drag strip on the left edge of the panel. Copy of the editor's
/// handle — kept local here so we don't couple the two screens on a shared
/// widget file until a third caller emerges.
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

class _ProcessingState extends StatelessWidget {
  const _ProcessingState();

  @override
  Widget build(BuildContext context) => const Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
}

class _SingleIssueBody extends StatelessWidget {
  final ValidationIssue issue;
  final int index;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final TwmtThemeTokens tokens;

  const _SingleIssueBody({
    required this.issue,
    required this.index,
    required this.total,
    required this.onEdit,
    required this.onAccept,
    required this.onReject,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Header(index: index, total: total, tokens: tokens),
        const SizedBox(height: 10),
        _KeyChip(text: issue.unitKey, tokens: tokens),
        const SizedBox(height: 10),
        _SeverityRow(
          severity: issue.severity,
          issueType: issue.issueType,
          description: issue.description,
          tokens: tokens,
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _TextBlock(
            label: 'SOURCE',
            text: issue.sourceText,
            tokens: tokens,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(
          child: _TextBlock(
            label: 'TRANSLATION',
            text: issue.translatedText,
            tokens: tokens,
            highlight: issue.severity,
          ),
        ),
        const SizedBox(height: 14),
        _ActionsRow(
          onEdit: onEdit,
          onAccept: onAccept,
          onReject: onReject,
          tokens: tokens,
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
            'Issue',
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

class _SeverityRow extends StatelessWidget {
  final ValidationSeverity severity;
  final String issueType;
  final String description;
  final TwmtThemeTokens tokens;
  const _SeverityRow({
    required this.severity,
    required this.issueType,
    required this.description,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) {
    final isError = severity == ValidationSeverity.error;
    final color = isError ? Colors.red[700]! : Colors.orange[700]!;
    final icon = isError
        ? FluentIcons.error_circle_24_filled
        : FluentIcons.warning_24_filled;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            issueType,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            description,
            style: TextStyle(color: tokens.textMid, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    );
  }
}

class _TextBlock extends StatelessWidget {
  final String label;
  final String text;
  final TwmtThemeTokens tokens;
  final ValidationSeverity? highlight;

  const _TextBlock({
    required this.label,
    required this.text,
    required this.tokens,
    this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    Color? fill;
    if (highlight != null) {
      final isError = highlight == ValidationSeverity.error;
      fill = isError
          ? Colors.red.withValues(alpha: 0.05)
          : Colors.orange.withValues(alpha: 0.05);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: tokens.fontMono.copyWith(
            fontSize: 9.5,
            color: tokens.textFaint,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: fill ?? tokens.panel2,
              border: Border.all(color: tokens.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
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
}

class _ActionsRow extends StatelessWidget {
  final VoidCallback onEdit;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final TwmtThemeTokens tokens;

  const _ActionsRow({
    required this.onEdit,
    required this.onAccept,
    required this.onReject,
    required this.tokens,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _ActionTile(
              label: 'Edit',
              icon: FluentIcons.edit_24_regular,
              color: Colors.blue[700]!,
              onTap: onEdit,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionTile(
              label: 'Accept',
              icon: FluentIcons.checkmark_24_regular,
              color: Colors.green[700]!,
              onTap: onAccept,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _ActionTile(
              label: 'Reject',
              icon: FluentIcons.dismiss_24_regular,
              color: Colors.red[700]!,
              onTap: onReject,
            ),
          ),
        ],
      );
}

class _ActionTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ActionTile({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Header shown when the user has selected multiple validation issues via
/// checkboxes. Mirrors the editor's `_MultiSelectHeader` but adds a hint
/// pointing the user at the toolbar's bulk Accept/Reject buttons.
class _MultiSelectHeader extends StatelessWidget {
  final int count;
  final TwmtThemeTokens tokens;
  const _MultiSelectHeader({required this.count, required this.tokens});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count issues selected',
            style: tokens.fontDisplay.copyWith(
              fontStyle: tokens.fontDisplayStyle,
              fontSize: 16,
              color: tokens.accent,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Use the toolbar buttons to accept or reject the selection in bulk.',
            style: TextStyle(color: tokens.textMid, fontSize: 12),
          ),
        ],
      );
}
