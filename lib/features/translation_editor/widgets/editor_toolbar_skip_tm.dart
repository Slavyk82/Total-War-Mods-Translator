import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import '../providers/translation_settings_provider.dart';

/// Toggleable "Skip TM" checkbox for the editor toolbar.
///
/// When enabled, the translation pipeline skips the translation memory lookup
/// and always queries the active LLM provider.
class EditorToolbarSkipTm extends ConsumerWidget {
  final bool compact;

  const EditorToolbarSkipTm({super.key, this.compact = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(translationSettingsProvider);
    final tokens = context.tokens;
    final activeColor = settings.skipTranslationMemory ? tokens.err : tokens.textMid;

    return Tooltip(
      message: TooltipStrings.editorSkipTm,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            ref.read(translationSettingsProvider.notifier)
                .setSkipTranslationMemory(!settings.skipTranslationMemory);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 8,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: settings.skipTranslationMemory
                  ? tokens.errBg
                  : Colors.transparent,
              border: Border.all(
                color: settings.skipTranslationMemory
                    ? tokens.err
                    : tokens.border,
              ),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  settings.skipTranslationMemory
                      ? FluentIcons.checkbox_checked_24_regular
                      : FluentIcons.checkbox_unchecked_24_regular,
                  size: 16,
                  color: activeColor,
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Skip TM',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: activeColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
