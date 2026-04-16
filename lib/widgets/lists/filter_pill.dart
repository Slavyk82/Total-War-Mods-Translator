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

  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onToggle,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bg = selected ? tokens.accentBg : tokens.panel2;
    final borderColor = selected ? tokens.accent : tokens.border;
    final labelColor = selected ? tokens.accent : tokens.textMid;
    return MouseRegion(
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
  }
}

/// A labelled group of [FilterPill]s — label caps-mono textDim + row of pills.
class FilterPillGroup extends StatelessWidget {
  final String label;
  final List<FilterPill> pills;

  const FilterPillGroup({super.key, required this.label, required this.pills});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: tokens.fontMono.copyWith(fontSize: 10, color: tokens.textDim, letterSpacing: 1.0)),
        const SizedBox(width: 8),
        for (var i = 0; i < pills.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          pills[i],
        ],
      ],
    );
  }
}
