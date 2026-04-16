import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// A toggleable filter pill per §6.2 of the UI spec.
/// Off: bg panel2 / fg textMid. On: bg accentBg / border accent / fg accent.
/// Radius follows tokens.radiusPill (20).
class FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final int? count;
  final VoidCallback onToggle;

  /// Optional tooltip shown on hover. Wraps the pill in a [Tooltip] when set.
  final String? tooltip;

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onToggle,
    this.count,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = selected ? tokens.accentBg : tokens.panel2;
    final borderColor = selected ? tokens.accent : tokens.border;
    final labelColor = selected ? tokens.accent : tokens.textMid;
    final core = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: tokens.fontBody.copyWith(fontSize: 12, color: labelColor)),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text('$count', style: tokens.fontMono.copyWith(fontSize: 11, color: tokens.textFaint)),
              ],
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return core;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: core,
    );
  }
}

/// A labelled group of [FilterPill]s — label caps-mono textDim + row of pills.
///
/// When [onClear] is provided and at least one pill is [FilterPill.selected],
/// a terminator "x {clearLabel}" pill is appended to deselect/reset the group.
class FilterPillGroup extends StatelessWidget {
  final String label;
  final List<FilterPill> pills;

  /// Callback invoked when the terminator clear pill is tapped.
  /// When null, the terminator pill is never rendered.
  final VoidCallback? onClear;

  /// Label shown on the terminator clear pill. Defaults to 'Clear'.
  final String? clearLabel;

  /// Optional tooltip for the terminator clear pill.
  final String? clearTooltip;

  const FilterPillGroup({
    super.key,
    required this.label,
    required this.pills,
    this.onClear,
    this.clearLabel,
    this.clearTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasActive = pills.any((p) => p.selected);
    final showClear = onClear != null && hasActive;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: tokens.fontMono.copyWith(fontSize: 10, color: tokens.textDim, letterSpacing: 1.0)),
        const SizedBox(width: 8),
        for (var i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          pills[i],
        ],
        if (showClear) ...[
          const SizedBox(width: 6),
          _FilterGroupClearPill(
            label: clearLabel ?? 'Clear',
            tooltip: clearTooltip,
            onTap: onClear!,
          ),
        ],
      ],
    );
  }
}

/// Terminator pill that deselects all sibling [FilterPill]s in a group.
/// Styled as a neutral outlined pill with a leading dismiss icon.
class _FilterGroupClearPill extends StatelessWidget {
  final String label;
  final String? tooltip;
  final VoidCallback onTap;

  const _FilterGroupClearPill({
    required this.label,
    required this.onTap,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final core = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusPill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.close, size: 12, color: tokens.textDim),
              const SizedBox(width: 4),
              Text(
                label,
                style: tokens.fontBody.copyWith(fontSize: 12, color: tokens.textDim),
              ),
            ],
          ),
        ),
      ),
    );
    if (tooltip == null) return core;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: core,
    );
  }
}
