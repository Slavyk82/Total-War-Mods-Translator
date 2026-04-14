import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/config/tooltip_strings.dart';
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
                  ? Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
              border: Border.all(
                color: settings.skipTranslationMemory
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).dividerColor,
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
                  color: settings.skipTranslationMemory
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
                if (!compact) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Skip TM',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: settings.skipTranslationMemory
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
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
