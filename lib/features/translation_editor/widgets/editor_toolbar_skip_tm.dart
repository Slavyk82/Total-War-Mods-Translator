import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/translation_settings_provider.dart';

/// Toggleable "Use translation memory" checkbox for the editor sidebar.
///
/// Checked (default) means the translation pipeline consults Translation Memory
/// before querying the LLM. Unchecked means every unit is sent directly to the
/// active LLM provider — a deliberate bypass that we surface visually with the
/// `err` palette so it doesn't go unnoticed.
///
/// In non-compact mode the widget renders at the same 36-px stretched-pill
/// footprint as the other sidebar buttons (Translate/Validate/…), so the
/// §AI Context stack reads as a uniform column. The underlying provider
/// stores the negative form (`skipTranslationMemory`); this widget only
/// inverts it at the UI layer.
class EditorToolbarSkipTm extends ConsumerWidget {
  final bool compact;

  const EditorToolbarSkipTm({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(translationSettingsProvider);
    final tokens = context.tokens;
    final useTm = !settings.skipTranslationMemory;
    // Only the bypass state deserves attention; the default (TM enabled) is
    // rendered neutrally.
    final warn = !useTm;
    final fg = warn ? tokens.err : tokens.text;
    final borderColor = warn ? tokens.err : tokens.border;
    final bg = warn ? tokens.errBg : tokens.panel2;

    final icon = Icon(
      useTm
          ? FluentIcons.checkbox_checked_24_regular
          : FluentIcons.checkbox_unchecked_24_regular,
      size: compact ? 16 : 14,
      color: fg,
    );

    void toggle() {
      ref
          .read(translationSettingsProvider.notifier)
          .setSkipTranslationMemory(!settings.skipTranslationMemory);
    }

    return Tooltip(
      message: t.tooltips.editor.useTm,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: toggle,
          child: compact
              ? _buildCompact(tokens, bg, borderColor, icon)
              : _buildFull(tokens, bg, borderColor, icon, fg),
        ),
      ),
    );
  }

  Widget _buildFull(
    TwmtThemeTokens tokens,
    Color bg,
    Color borderColor,
    Widget icon,
    Color fg,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(tokens.radiusSm),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              t.translationEditor.toolbar.useTranslationMemory,
              overflow: TextOverflow.ellipsis,
              style: tokens.fontBody.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompact(
    TwmtThemeTokens tokens,
    Color bg,
    Color borderColor,
    Widget icon,
  ) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: icon,
    );
  }
}
