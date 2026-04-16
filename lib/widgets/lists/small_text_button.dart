import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Small outlined text button used inside list toolbars and selection bars.
///
/// Token-themed: panel2 background, border outline, textMid label. Height 28.
/// Optionally wrapped in a [Tooltip] and prefixed with an [IconData] icon.
class SmallTextButton extends StatelessWidget {
  /// Label displayed on the button.
  final String label;

  /// Optional hover tooltip message.
  final String? tooltip;

  /// Tap callback. When null, the button is visually present but non-interactive.
  final VoidCallback? onTap;

  /// Optional leading icon. Rendered at 14px in [TwmtThemeTokens.textMid].
  final IconData? icon;

  const SmallTextButton({
    super.key,
    required this.label,
    this.tooltip,
    this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final core = MouseRegion(
      cursor:
          onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: tokens.panel2,
            border: Border.all(color: tokens.border),
            borderRadius: BorderRadius.circular(tokens.radiusSm),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: tokens.textMid),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: tokens.textMid,
                  fontWeight: FontWeight.w500,
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
