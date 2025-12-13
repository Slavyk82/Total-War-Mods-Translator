import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../widgets/common/fluent_spinner.dart';
import '../../../../models/domain/language.dart';
import '../../providers/projects_screen_providers.dart';
import 'project_creation_state.dart';

/// Step 2: Target languages selection.
///
/// Allows selection of one or more target languages for translation.
class StepLanguages extends ConsumerWidget {
  final ProjectCreationState state;

  const StepLanguages({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final languagesAsync = ref.watch(allLanguagesProvider);

    return languagesAsync.when(
      data: (languages) => _buildLanguagesList(languages, theme),
      loading: () => const Center(child: FluentSpinner()),
      error: (err, stack) => _buildErrorState(err, theme, ref),
    );
  }

  Widget _buildLanguagesList(List<Language> languages, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select target languages for translation',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        ...languages.where((lang) => lang.isActive).map((language) {
          final isSelected = state.selectedLanguageIds.contains(language.id);
          return _LanguageCheckboxItem(
            language: language,
            isSelected: isSelected,
            state: state,
          );
        }),
      ],
    );
  }

  Widget _buildErrorState(Object err, ThemeData theme, WidgetRef ref) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          FluentIcons.error_circle_24_regular,
          color: theme.colorScheme.error,
          size: 48,
        ),
        const SizedBox(height: 16),
        Text(
          'Error loading languages',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          err.toString(),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        _FluentRetryButton(
          onTap: () {
            ref.invalidate(allLanguagesProvider);
          },
        ),
      ],
    );
  }
}

/// Individual language checkbox item following Fluent Design patterns.
class _LanguageCheckboxItem extends StatefulWidget {
  final Language language;
  final bool isSelected;
  final ProjectCreationState state;

  const _LanguageCheckboxItem({
    required this.language,
    required this.isSelected,
    required this.state,
  });

  @override
  State<_LanguageCheckboxItem> createState() => _LanguageCheckboxItemState();
}

class _LanguageCheckboxItemState extends State<_LanguageCheckboxItem> {
  void _toggleSelection() {
    setState(() {
      if (widget.isSelected) {
        widget.state.selectedLanguageIds.remove(widget.language.id);
      } else {
        widget.state.selectedLanguageIds.add(widget.language.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _toggleSelection,
          child: Row(
            children: [
              FluentCheckbox(
                value: widget.isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value) {
                      widget.state.selectedLanguageIds.add(widget.language.id);
                    } else {
                      widget.state.selectedLanguageIds.remove(widget.language.id);
                    }
                  });
                },
              ),
              const SizedBox(width: 12),
              Text(
                widget.language.displayName,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fluent Design retry button.
class _FluentRetryButton extends StatefulWidget {
  final VoidCallback onTap;

  const _FluentRetryButton({required this.onTap});

  @override
  State<_FluentRetryButton> createState() => _FluentRetryButtonState();
}

class _FluentRetryButtonState extends State<_FluentRetryButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: _isHovered
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                FluentIcons.arrow_sync_24_regular,
                size: 16,
                color: theme.colorScheme.onSurface,
              ),
              const SizedBox(width: 8),
              Text(
                'Retry',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
