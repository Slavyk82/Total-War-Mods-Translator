import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';

import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/language_selection_tile.dart';

import '../../../../models/domain/language.dart';
import '../../providers/projects_screen_providers.dart';
import 'project_creation_state.dart';

/// Step 2: Target languages selection.
///
/// Allows selection of one or more target languages for translation.
///
/// Retokenised (Plan 5d · Task 6): grid of token-themed [LanguageSelectionTile]
/// cells, accent-highlighted selected state, [SmallTextButton] for Select All /
/// Clear.
class StepLanguages extends ConsumerStatefulWidget {
  final ProjectCreationState state;

  const StepLanguages({
    super.key,
    required this.state,
  });

  @override
  ConsumerState<StepLanguages> createState() => _StepLanguagesState();
}

class _StepLanguagesState extends ConsumerState<StepLanguages> {
  void _toggle(String languageId) {
    setState(() {
      if (widget.state.selectedLanguageIds.contains(languageId)) {
        widget.state.selectedLanguageIds.remove(languageId);
      } else {
        widget.state.selectedLanguageIds.add(languageId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final languagesAsync = ref.watch(allLanguagesProvider);

    return languagesAsync.when(
      data: (languages) => _buildLanguagesList(languages, tokens),
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
      error: (err, stack) => _buildErrorState(err, tokens),
    );
  }

  Widget _buildLanguagesList(List<Language> languages, TwmtThemeTokens tokens) {
    final activeLanguages = languages.where((l) => l.isActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select one or more target languages for translation.',
          style: tokens.fontBody.copyWith(
            fontSize: 13,
            color: tokens.textDim,
          ),
        ),
        const SizedBox(height: 14),

        // Quick actions
        Row(
          children: [
            SmallTextButton(
              label: 'Select All',
              icon: FluentIcons.select_all_on_24_regular,
              onTap: () {
                setState(() {
                  for (final lang in activeLanguages) {
                    widget.state.selectedLanguageIds.add(lang.id);
                  }
                });
              },
            ),
            const SizedBox(width: 8),
            SmallTextButton(
              label: 'Clear',
              icon: FluentIcons.select_all_off_24_regular,
              onTap: () {
                setState(() {
                  widget.state.selectedLanguageIds.clear();
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Languages grid
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: activeLanguages.map((language) {
            final isSelected =
                widget.state.selectedLanguageIds.contains(language.id);
            return LanguageSelectionTile(
              language: language,
              isSelected: isSelected,
              onTap: () => _toggle(language.id),
            );
          }).toList(),
        ),

        if (widget.state.selectedLanguageIds.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            '${widget.state.selectedLanguageIds.length} language(s) selected',
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

  Widget _buildErrorState(Object err, TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            'Error loading languages',
            style: tokens.fontBody.copyWith(
              fontSize: 14,
              color: tokens.err,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            err.toString(),
            style: tokens.fontBody.copyWith(
              fontSize: 12.5,
              color: tokens.textDim,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          SmallTextButton(
            label: 'Retry',
            icon: FluentIcons.arrow_sync_24_regular,
            onTap: () => ref.invalidate(allLanguagesProvider),
          ),
        ],
      ),
    );
  }
}

