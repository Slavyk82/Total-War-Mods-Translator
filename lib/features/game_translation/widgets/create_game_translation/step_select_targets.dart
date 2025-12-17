import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import '../../../../models/domain/language.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../projects/providers/projects_screen_providers.dart';
import '../../../settings/providers/language_settings_providers.dart';
import 'add_language_wizard_dialog.dart';
import 'game_translation_creation_state.dart';

/// Step 2: Select target languages for translation
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
    final theme = Theme.of(context);
    final languagesAsync = ref.watch(allLanguagesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Target Languages',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose the languages you want to translate the game into.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 16),

        // Source language info
        if (state.selectedSourcePack != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  FluentIcons.arrow_right_24_regular,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Translating from: ',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  state.selectedSourcePack!.languageName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

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
              return _buildNoLanguages(theme);
            }

            return _buildLanguagesList(context, theme, availableLanguages, ref);
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => _buildError(theme, e.toString()),
        ),

        // Selection summary
        if (state.selectedLanguageIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${state.selectedLanguageIds.length} language(s) selected',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNoLanguages(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        children: [
          Icon(
            FluentIcons.warning_24_regular,
            size: 48,
            color: theme.colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            'No languages available',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Please configure target languages in Settings.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLanguagesList(
    BuildContext context,
    ThemeData theme,
    List<Language> languages,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Quick actions
        Row(
          children: [
            TextButton.icon(
              onPressed: () {
                for (final lang in languages) {
                  if (!state.selectedLanguageIds.contains(lang.id)) {
                    state.selectedLanguageIds.add(lang.id);
                  }
                }
                onStateChanged();
              },
              icon: const Icon(FluentIcons.select_all_on_24_regular, size: 16),
              label: const Text('Select All'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                state.clearLanguages();
                onStateChanged();
              },
              icon: const Icon(FluentIcons.select_all_off_24_regular, size: 16),
              label: const Text('Clear'),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showAddLanguageDialog(context, ref),
              icon: const Icon(FluentIcons.add_24_regular, size: 16),
              label: const Text('Add Language'),
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
            return _LanguageChip(
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

  Widget _buildError(ThemeData theme, String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              error,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

/// A language selection chip following Fluent Design patterns
class _LanguageChip extends StatefulWidget {
  final Language language;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageChip({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_LanguageChip> createState() => _LanguageChipState();
}

class _LanguageChipState extends State<_LanguageChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color backgroundColor;
    if (widget.isSelected) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.15);
    } else if (_isHovered) {
      backgroundColor = theme.colorScheme.primary.withValues(alpha: 0.08);
    } else {
      backgroundColor = theme.colorScheme.surface;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: widget.isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isSelected)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    FluentIcons.checkmark_24_regular,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                ),
              Text(
                widget.language.displayName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.isSelected ? theme.colorScheme.primary : null,
                  fontWeight: widget.isSelected ? FontWeight.w600 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
