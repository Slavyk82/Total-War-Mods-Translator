import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Stateful on/off chip with an optional count badge and leading icon.
///
/// Distinct from [SmallTextButton] (stateless action) and [FilterPill]
/// (group-filter pill with radiusPill). Used for toolbar toggles such as
/// "Hidden" in the Mods screen and (Task 4+) batch-selection chips in
/// the Glossary / TM screens.
///
/// Visual (per §6.3):
/// - 32px height, radiusMd, padding `horizontal: 10px vertical: 6px`.
/// - Off: bg `panel2`, border `border`, fg `textMid`.
/// - On: bg `accentBg`, border `accent`, fg `accent`.
/// - Count badge rendered inline in font-mono: `textFaint` (off) /
///   `accent` (on).
class ToggleChip extends StatelessWidget {
  /// Label displayed on the chip.
  final String label;

  /// Current on/off state.
  final bool selected;

  /// Called when the chip is tapped. Callers are expected to flip [selected]
  /// themselves in response.
  final VoidCallback onToggle;

  /// Optional badge count rendered after the label in the mono font.
  final int? count;

  /// Optional leading icon rendered at 14px in the foreground color.
  final IconData? icon;

  /// Optional hover tooltip. When set, the chip is wrapped in a [Tooltip].
  final String? tooltip;

  const ToggleChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onToggle,
    this.count,
    this.icon,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fg = selected ? tokens.accent : tokens.textMid;
    final bg = selected ? tokens.accentBg : tokens.panel2;
    final borderColor = selected ? tokens.accent : tokens.border;
    final countColor = selected ? tokens.accent : tokens.textFaint;

    final core = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onToggle,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusMd),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: fg,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: tokens.fontMono.copyWith(
                    fontSize: 11,
                    color: countColor,
                  ),
                ),
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
