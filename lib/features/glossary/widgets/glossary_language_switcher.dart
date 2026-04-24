import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';

/// Language switcher chip + popover for the glossary screen.
///
/// Renders an accent chip showing the currently selected language of the
/// `(gameCode, targetLanguageId)`-scoped glossary. Tapping the chip opens a
/// menu listing every language declared on any project of [gameCode] (driven
/// by [glossaryAvailableLanguagesProvider]). Selecting a language persists
/// the choice via [selectedGlossaryLanguageProvider]. There is deliberately
/// no delete button and no "add language" affordance — the list is purely a
/// read-only projection of the project-language configuration.
class GlossaryLanguageSwitcher extends ConsumerWidget {
  const GlossaryLanguageSwitcher({
    super.key,
    required this.gameCode,
    required this.currentLanguageId,
  });

  final String gameCode;
  final String? currentLanguageId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final langsAsync = ref.watch(glossaryAvailableLanguagesProvider(gameCode));
    final langs = langsAsync.asData?.value ?? const <Language>[];
    final current = langs.where((l) => l.id == currentLanguageId).firstOrNull;

    return MenuAnchor(
      alignmentOffset: const Offset(0, 4),
      builder: (context, controller, _) {
        return _SwitcherChip(
          key: const Key('glossary-language-switcher-chip'),
          label: current?.name ?? '—',
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
        );
      },
      menuChildren: [
        if (langs.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('No languages available',
                style: tokens.fontBody
                    .copyWith(fontSize: 12, color: tokens.textDim)),
          )
        else
          for (final l in langs)
            _LanguageMenuItem(
              key: Key('glossary-language-switcher-item-${l.id}'),
              language: l,
              isCurrent: l.id == currentLanguageId,
              onSelect: () => ref
                  .read(selectedGlossaryLanguageProvider(gameCode).notifier)
                  .setLanguageId(gameCode, l.id),
            ),
      ],
    );
  }
}

class _SwitcherChip extends StatelessWidget {
  const _SwitcherChip({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.accentBg,
      borderRadius: BorderRadius.circular(tokens.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(FluentIcons.globe_24_regular,
                  size: 16, color: tokens.accent),
              const SizedBox(width: 6),
              Text(label,
                  style: tokens.fontBody.copyWith(
                      fontSize: 13,
                      color: tokens.accent,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 4),
              Icon(FluentIcons.chevron_down_24_regular,
                  size: 14, color: tokens.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageMenuItem extends StatelessWidget {
  const _LanguageMenuItem({
    super.key,
    required this.language,
    required this.isCurrent,
    required this.onSelect,
  });
  final Language language;
  final bool isCurrent;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onSelect,
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(
                isCurrent
                    ? FluentIcons.checkmark_24_regular
                    : FluentIcons.translate_24_regular,
                size: 16,
                color: isCurrent ? tokens.accent : tokens.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(language.name,
                    style: tokens.fontBody
                        .copyWith(fontSize: 13, color: tokens.text)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
