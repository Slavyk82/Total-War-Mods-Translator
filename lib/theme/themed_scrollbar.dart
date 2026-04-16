import 'package:flutter/material.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Builds a [ScrollbarThemeData] matching the TWMT design language:
///   - Flutter default thickness (Material 3 baseline).
///   - Thumb uses `tokens.border` at rest, `tokens.accent` on hover/press.
///   - Track transparent.
ScrollbarThemeData themedScrollbar(TwmtThemeTokens t) {
  return ScrollbarThemeData(
    thumbVisibility: const WidgetStatePropertyAll(true),
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
    interactive: true,
  );
}
