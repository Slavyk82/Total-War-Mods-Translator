import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Builds a [ScrollbarThemeData] matching the TWMT design language:
///   - 20 px track thickness (vertical and horizontal).
///   - Thumb uses `tokens.border` at rest, `tokens.accent` on hover/press.
///   - Radius 10 (half of thickness — fully rounded thumb).
///   - Arrow buttons hidden (thumbVisibility is true so the bar itself is
///     always drawn when needed).
///   - 5 logical pixels of transparent padding around the thumb for breathing
///     room — implemented via `MaterialStatePropertyAll` on `thickness` plus
///     `RoundedRectangleBorder` on `shape`.
ScrollbarThemeData themedScrollbar(TwmtThemeTokens t) {
  return ScrollbarThemeData(
    thumbVisibility: const WidgetStatePropertyAll(true),
    thickness: const WidgetStatePropertyAll(20.0),
    radius: const Radius.circular(10.0),
    trackVisibility: const WidgetStatePropertyAll(false),
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.dragged)) {
        return t.accent;
      }
      return t.border;
    }),
    trackColor: const WidgetStatePropertyAll(Colors.transparent),
    trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
    crossAxisMargin: 5.0,
    mainAxisMargin: 5.0,
    interactive: true,
  );
}
