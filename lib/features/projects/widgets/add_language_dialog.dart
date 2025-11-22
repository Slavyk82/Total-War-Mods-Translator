import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import '../../../models/domain/language.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/translation_version.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../providers/projects_screen_providers.dart';
import '../providers/project_detail_providers.dart';

/// Dialog for adding target languages to a project.
///
/// Allows selecting one or more languages from the available languages list.
/// Languages already in the project are filtered out.
class AddLanguageDialog extends ConsumerStatefulWidget {
  final String projectId;
  final List<String> existingLanguageIds;

  const AddLanguageDialog({
    super.key,
    required this.projectId,
    required this.existingLanguageIds,
  });

  @override
  ConsumerState<AddLanguageDialog> createState() => _AddLanguageDialogState();
}

class _AddLanguageDialogState extends ConsumerState<AddLanguageDialog> {
  final Set<String> _selectedLanguageIds = {};
  bool _isLoading = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final languagesAsync = ref.watch(allLanguagesProvider);

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(
            FluentIcons.add_circle_24_regular,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Add Target Languages'),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Error message
            if (_errorMessage != null) ...[
              _buildErrorBanner(theme),
              const SizedBox(height: 16),
            ],

            // Instructions
            Text(
              'Select languages to add to this project',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),

            // Languages list
            Expanded(
              child: languagesAsync.when(
                data: (languages) => _buildLanguagesList(languages, theme),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, stack) => _buildErrorState(theme, err),
              ),
            ),
          ],
        ),
      ),
      actions: [
        _FluentDialogButton(
          icon: FluentIcons.dismiss_24_regular,
          label: 'Cancel',
          onTap: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        _FluentDialogButton(
          icon: FluentIcons.checkmark_24_regular,
          label: 'Add Languages',
          isPrimary: true,
          isLoading: _isLoading,
          onTap: _selectedLanguageIds.isEmpty || _isLoading
              ? null
              : () => _addLanguages(context),
        ),
      ],
    );
  }

  Widget _buildLanguagesList(List<Language> allLanguages, ThemeData theme) {
    // Filter out languages already in the project and inactive languages
    final availableLanguages = allLanguages
        .where((lang) =>
            lang.isActive && !widget.existingLanguageIds.contains(lang.id))
        .toList();

    if (availableLanguages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              FluentIcons.checkmark_circle_24_regular,
              size: 48,
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'All languages already added',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: availableLanguages.length,
      itemBuilder: (context, index) {
        final language = availableLanguages[index];
        final isSelected = _selectedLanguageIds.contains(language.id);
        return _buildLanguageCheckbox(language, isSelected, theme);
      },
    );
  }

  Widget _buildLanguageCheckbox(
    Language language,
    bool isSelected,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () {
            setState(() {
              if (isSelected) {
                _selectedLanguageIds.remove(language.id);
              } else {
                _selectedLanguageIds.add(language.id);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.3)
                    : theme.colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                FluentCheckbox(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value) {
                        _selectedLanguageIds.add(language.id);
                      } else {
                        _selectedLanguageIds.remove(language.id);
                      }
                    });
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        language.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Code: ${language.code.toUpperCase()}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.textTheme.bodySmall?.color
                              ?.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: theme.colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _errorMessage!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            size: 48,
            color: theme.colorScheme.error,
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
            error.toString(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _addLanguages(BuildContext context) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final projectLangRepo = ref.read(projectLanguageRepositoryProvider);
      final translationUnitRepo = ref.read(translationUnitRepositoryProvider);
      final translationVersionRepo = ref.read(translationVersionRepositoryProvider);
      const uuid = Uuid();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Get all translation units for this project
      final unitsResult = await translationUnitRepo.getByProject(widget.projectId);

      if (unitsResult.isErr) {
        throw Exception('Failed to load translation units: ${unitsResult.error}');
      }

      final translationUnits = unitsResult.unwrap();

      // Convert Set to List to avoid concurrent modification
      final languageIdsList = _selectedLanguageIds.toList();

      // Add each selected language to the project
      for (final languageId in languageIdsList) {
        // Create project_language entry
        final projectLanguageId = uuid.v4();
        final projectLanguage = ProjectLanguage(
          id: projectLanguageId,
          projectId: widget.projectId,
          languageId: languageId,
          progressPercent: 0.0,
          createdAt: now,
          updatedAt: now,
        );

        final result = await projectLangRepo.insert(projectLanguage);

        if (result.isErr) {
          throw Exception('Failed to add language: ${result.error}');
        }

        // Create translation_versions entries for all existing translation_units
        // Use batch insert for better performance
        final versionsToInsert = <TranslationVersion>[];
        for (final unit in translationUnits) {
          versionsToInsert.add(TranslationVersion(
            id: uuid.v4(),
            unitId: unit.id,
            projectLanguageId: projectLanguageId,
            translatedText: null,
            isManuallyEdited: false,
            status: TranslationVersionStatus.pending,
            createdAt: now,
            updatedAt: now,
          ));
        }

        // Insert all versions for this language in one batch
        final versionResult = await translationVersionRepo.insertBatch(versionsToInsert);

        if (versionResult.isErr) {
          throw Exception('Failed to create translation versions: ${versionResult.error}');
        }
      }

      if (!context.mounted) return;

      // Refresh project details
      ref.invalidate(projectDetailsProvider(widget.projectId));

      // Show success message
      FluentToast.success(
        context,
        'Added ${languageIdsList.length} language${languageIdsList.length > 1 ? 's' : ''} with ${translationUnits.length} translation units each',
      );

      // Close dialog
      Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to add languages: $e';
        _isLoading = false;
      });
    }
  }
}

/// Fluent Design dialog button
class _FluentDialogButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isLoading;

  const _FluentDialogButton({
    required this.icon,
    required this.label,
    this.onTap,
    this.isPrimary = false,
    this.isLoading = false,
  });

  @override
  State<_FluentDialogButton> createState() => _FluentDialogButtonState();
}

class _FluentDialogButtonState extends State<_FluentDialogButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null && !widget.isLoading;

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isPrimary
                ? (_isHovered && isEnabled
                    ? theme.colorScheme.primary.withValues(alpha: 0.9)
                    : theme.colorScheme.primary)
                : (_isHovered && isEnabled
                    ? theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(6),
            border: widget.isPrimary
                ? null
                : Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.isLoading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: widget.isPrimary
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  widget.icon,
                  size: 16,
                  color: isEnabled
                      ? (widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              const SizedBox(width: 8),
              Text(
                widget.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isEnabled
                      ? (widget.isPrimary
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.3),
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
