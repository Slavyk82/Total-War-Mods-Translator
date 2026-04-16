import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Small square icon-only button used in list toolbars and row actions.
///
/// Token-themed by default (`tokens.panel2` fill, `tokens.border` outline,
/// `tokens.textMid` icon). Callers can override [foreground] / [background] /
/// [borderColor] to render accent or destructive variants (e.g. delete =
/// `tokens.err`).
///
/// [size] defaults to 28 (matches [SmallTextButton] height for row-action
/// clusters). Toolbar trailing actions use 32.
class SmallIconButton extends StatelessWidget {
  /// Icon rendered at [iconSize] in [foreground] (or `tokens.textMid`).
  final IconData icon;

  /// Hover tooltip message.
  final String tooltip;

  /// Tap callback.
  final VoidCallback onTap;

  /// Square edge length. Defaults to 28.
  final double size;

  /// Icon size. Defaults to 14.
  final double iconSize;

  /// Foreground / icon color. Falls back to `tokens.textMid` when null.
  final Color? foreground;

  /// Background fill color. Falls back to `tokens.panel2` when null.
  final Color? background;

  /// Border color. Falls back to `tokens.border` when null.
  final Color? borderColor;

  const SmallIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 28,
    this.iconSize = 14,
    this.foreground,
    this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: size,
            width: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background ?? tokens.panel2,
              border: Border.all(color: borderColor ?? tokens.border),
              borderRadius: BorderRadius.circular(tokens.radiusSm),
            ),
            child: Icon(
              icon,
              size: iconSize,
              color: foreground ?? tokens.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
