import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Small text button used inside list toolbars, selection bars, and dialog
/// action rows.
///
/// Default (outlined) variant: panel2 background, border outline, textMid
/// label/icon. Height 28.
///
/// Filled variant ([filled] = true): accent background, accent border,
/// accentFg label/icon — used for primary/affirmative dialog actions.
///
/// Optionally wrapped in a [Tooltip] and prefixed with an [IconData] icon.
class SmallTextButton extends StatelessWidget {
  /// Label displayed on the button.
  final String label;

  /// Optional hover tooltip message.
  final String? tooltip;

  /// Tap callback. When null, the button is visually present but non-interactive.
  final VoidCallback? onTap;

  /// Optional leading icon. Rendered at 14px; colour follows the variant.
  final IconData? icon;

  /// When true, renders the accent-filled variant. Defaults to false
  /// (outlined).
  final bool filled;

  const SmallTextButton({
    super.key,
    required this.label,
    this.tooltip,
    this.onTap,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final bgColor = filled ? tokens.accent : tokens.panel2;
    final fgColor = filled ? tokens.accentFg : tokens.textMid;
    final borderColor = filled ? tokens.accent : tokens.border;

    final core = MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: bgColor,
            border: Border.all(color: borderColor),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: fgColor),
                const SizedBox(width: 6),
              ],
              // `Flexible` keeps the button at its intrinsic width in
              // unbounded parents (existing callers), but lets the label
              // shrink + ellipsize when constrained — required so long
              // labels in narrow hosts (e.g. the 240 px editor sidebar)
              // don't overflow their Row.
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.fontBody.copyWith(
                    fontSize: 12.5,
                    color: fgColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
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
