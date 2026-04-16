import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Cell widget for the "TM" column.
///
/// Renders the translation provenance (Exact / Fuzzy / LLM / Manual / none)
/// as a coloured badge pill instead of plain text, mirroring the editor
/// mockup. Uses palette tokens for OK / WARN colours and a fixed lavender
/// for the LLM badge so the colour stays distinct from validation states.
class TmSourceCellRenderer extends StatelessWidget {
  final TranslationSource source;

  /// Distinguishes manually-edited rows from rows whose stored
  /// `translationSource` is itself `manual`. Both render the "MANUAL" badge.
  final bool manuallyEdited;

  /// Forwarded so right-clicking the badge still opens the row context menu.
  final void Function(Offset globalPosition)? onSecondaryTap;

  const TmSourceCellRenderer({
    super.key,
    required this.source,
    required this.manuallyEdited,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spec = _resolveBadge(tokens);

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Listener(
        onPointerDown: (event) {
          if (event.buttons == kSecondaryMouseButton) {
            onSecondaryTap?.call(event.position);
          }
        },
        behavior: HitTestBehavior.translucent,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: spec.background,
              border: spec.borderColor != null
                  ? Border.all(color: spec.borderColor!)
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              spec.label,
              style: tokens.fontMono.copyWith(
                fontSize: 9.5,
                color: spec.foreground,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }

  _BadgeSpec _resolveBadge(TwmtThemeTokens tokens) {
    // Fixed lavender for LLM badges. Kept outside the theme tokens because
    // none of the existing semantic colours (ok / warn / accent) carry the
    // "AI generated" connotation called out in the mockup.
    const llmFg = Color(0xFFB09EDC);
    const llmBg = Color(0x33B09EDC);

    if (manuallyEdited) {
      return _BadgeSpec(
        label: 'MANUAL',
        background: tokens.panel2,
        foreground: tokens.textFaint,
      );
    }

    return switch (source) {
      TranslationSource.tmExact => _BadgeSpec(
          label: 'EXACT',
          background: tokens.ok.withValues(alpha: 0.18),
          foreground: tokens.ok,
        ),
      TranslationSource.tmFuzzy => _BadgeSpec(
          label: 'FUZZY',
          background: tokens.warn.withValues(alpha: 0.18),
          foreground: tokens.warn,
        ),
      TranslationSource.llm => const _BadgeSpec(
          label: 'LLM',
          background: llmBg,
          foreground: llmFg,
        ),
      TranslationSource.manual => _BadgeSpec(
          label: 'MANUAL',
          background: tokens.panel2,
          foreground: tokens.textFaint,
        ),
      TranslationSource.unknown => _BadgeSpec(
          // Em dash matches the existing empty-cell affordance.
          label: '—',
          background: Colors.transparent,
          foreground: tokens.textFaint,
          borderColor: tokens.border,
        ),
    };
  }
}

class _BadgeSpec {
  final String label;
  final Color background;
  final Color foreground;
  final Color? borderColor;

  const _BadgeSpec({
    required this.label,
    required this.background,
    required this.foreground,
    this.borderColor,
  });
}
