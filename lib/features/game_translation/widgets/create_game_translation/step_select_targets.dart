import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';

import '../../../../models/domain/language.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../widgets/lists/small_text_button.dart';
import '../../../projects/providers/projects_screen_providers.dart';
import '../../../settings/providers/language_settings_providers.dart';
import 'add_language_wizard_dialog.dart';
import 'game_translation_creation_state.dart';

/// Step 2: select target languages for translation.
///
/// Retokenised (Plan 5d · Task 5): tokens on banner / chips / helper texts,
/// Select-All / Clear / Add-Language actions switch to [SmallTextButton].
class StepSelectTargets extends ConsumerWidget {
  final GameTranslationCreationState state;
  final VoidCallback onStateChanged;

  const StepSelectTargets({
    super.key,
    required this.state,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final languagesAsync = ref.watch(allLanguagesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the languages you want to translate the game into.',
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 14),

        // Source language info
        if (state.selectedSourcePack != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.accentBg,
              borderRadius: BorderRadius.circular(tokens.radiusSm),
              border: Border.all(color: tokens.accent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.arrow_right_24_regular,
                  color: tokens.accent,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Translating from: ',
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.text,
                  ),
                ),
                Text(
                  state.selectedSourcePack!.languageName,
                  style: tokens.fontBody.copyWith(
                    fontSize: 13,
                    color: tokens.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 20),

        // Languages list
        languagesAsync.when(
          data: (languages) {
            // Filter out the source language
            final sourceCode =
                state.selectedSourcePack?.languageCode.toLowerCase();
            final availableLanguages = languages
                .where((lang) => lang.code.toLowerCase() != sourceCode)
                .toList();

            if (availableLanguages.isEmpty) {
              return _buildNoLanguages(tokens);
            }

            return _buildLanguagesList(context, tokens, availableLanguages, ref);
          },
          loading: () => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
                ),
              ),
            ),
          ),
          error: (e, _) => _buildError(tokens, e.toString()),
        ),

        // Selection summary
        if (state.selectedLanguageIds.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '${state.selectedLanguageIds.length} language(s) selected',
            style: tokens.fontBody.copyWith(
              fontSize: 12,
              color: tokens.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoLanguages(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: tokens.panel2,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Icon(
            FluentIcons.warning_24_regular,
            size: 40,
            color: tokens.err,
          ),
          const SizedBox(height: 10),
          Text(
            'No languages available',
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Please configure target languages in Settings.',
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagesList(
    BuildContext context,
    TwmtThemeTokens tokens,
    List<Language> languages,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick actions
        Row(
          children: [
            SmallTextButton(
              label: 'Select All',
              icon: FluentIcons.select_all_on_24_regular,
              onTap: () {
                for (final lang in languages) {
                  if (!state.selectedLanguageIds.contains(lang.id)) {
                    state.selectedLanguageIds.add(lang.id);
                  }
                }
                onStateChanged();
              },
            ),
            const SizedBox(width: 8),
            SmallTextButton(
              label: 'Clear',
              icon: FluentIcons.select_all_off_24_regular,
              onTap: () {
                state.clearLanguages();
                onStateChanged();
              },
            ),
            const Spacer(),
            SmallTextButton(
              label: 'Add Language',
              icon: FluentIcons.add_24_regular,
              onTap: () => _showAddLanguageDialog(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Languages grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: languages.map((language) {
            final isSelected = state.isLanguageSelected(language.id);
            return _LanguageTile(
              language: language,
              isSelected: isSelected,
              onTap: () {
                state.toggleLanguage(language.id);
                onStateChanged();
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Future<void> _showAddLanguageDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showDialog<AddLanguageWizardResult>(
      context: context,
      builder: (context) => const AddLanguageWizardDialog(),
    );

    if (result != null && context.mounted) {
      // Add the new language
      final (success, error) =
          await ref.read(languageSettingsProvider.notifier).addCustomLanguage(
                code: result.code,
                name: result.name,
              );

      if (!context.mounted) return;

      if (success) {
        // If user wants to set as default, do so
        if (result.setAsDefault) {
          await ref
              .read(languageSettingsProvider.notifier)
              .setDefaultLanguage(result.code);
        }

        if (!context.mounted) return;
        FluentToast.success(
          context,
          result.setAsDefault
              ? 'Language "${result.name}" added and set as default'
              : 'Language "${result.name}" added successfully',
        );

        // Refresh the languages list
        ref.invalidate(allLanguagesProvider);
        onStateChanged();
      } else {
        FluentToast.error(context, error ?? 'Failed to add language');
      }
    }
  }

  Widget _buildError(TwmtThemeTokens tokens, String error) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: tokens.fontBody.copyWith(
                fontSize: 13,
                color: tokens.err,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A language selection tile — token themed grid cell.
class _LanguageTile extends StatefulWidget {
  final Language language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_LanguageTile> createState() => _LanguageTileState();
}

class _LanguageTileState extends State<_LanguageTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    final Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = tokens.accentBg;
    } else if (_isHovered) {
      backgroundColor = tokens.panel;
    } else {
      backgroundColor = tokens.panel2;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(
              color: widget.isSelected ? tokens.accent : tokens.border,
              width: widget.isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Icon(
                    FluentIcons.checkmark_24_regular,
                    size: 14,
                    color: tokens.accent,
                  ),
                ),
              Text(
                widget.language.displayName,
                style: tokens.fontBody.copyWith(
                  fontSize: 12.5,
                  color: widget.isSelected ? tokens.accent : tokens.text,
                  fontWeight:
                      widget.isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
