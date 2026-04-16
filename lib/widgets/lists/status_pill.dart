import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Small status/state badge per §6.3 of the UI spec.
///
/// These are readonly state indicators — NOT togglable filters. They use
/// `tokens.radiusMd` (8px) rather than [TwmtThemeTokens.radiusPill], a
/// mono-cap label at 10px and a hairline border tinted from [foreground].
///
/// Callers supply their own foreground/background colors so a single
/// primitive can cover success/warn/err/neutral surfaces.
///
/// When [onTap] is provided the pill becomes clickable (click cursor +
/// tap target). When [tooltip] is provided the pill is wrapped in a
/// hover Tooltip.
class StatusPill extends StatelessWidget {
  /// Label rendered inside the pill.
  final String label;

  /// Foreground color (used for label, icon and tinted border).
  final Color foreground;

  /// Background fill color.
  final Color background;

  /// Optional leading icon rendered at 12px in [foreground].
  final IconData? icon;

  /// Optional hover tooltip. When null, the pill is not wrapped in a Tooltip.
  final String? tooltip;

  /// Tap callback. When null, the pill is visual-only.
  final VoidCallback? onTap;

  const StatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget core = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        border: Border.all(color: foreground.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontMono.copyWith(
                fontSize: 10,
                color: foreground,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ],
      ),
    );

    if (onTap != null) {
      core = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: core,
        ),
      );
    }

    if (tooltip == null) return core;
    return Tooltip(
      message: tooltip!,
      waitDuration: const Duration(milliseconds: 400),
      child: core,
    );
  }
}
