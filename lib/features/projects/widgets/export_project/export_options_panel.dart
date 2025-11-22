import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import '../../../../models/domain/export_history.dart';
import '../../../../models/domain/project_language.dart';
import '../../../../models/domain/language.dart';
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../providers/projects_screen_providers.dart';

/// Export options panel including language selection and validation options.
///
/// Displays:
/// - List of available languages with checkboxes
/// - Progress percentage for each language
/// - Validated-only checkbox option
/// - Output folder selection
/// - Format-specific hints
class ExportOptionsPanel extends ConsumerWidget {
  final String projectId;
  final Set<String> selectedLanguageIds;
  final ValueChanged<Set<String>> onLanguageSelectionChanged;
  final bool validatedOnly;
  final ValueChanged<bool> onValidatedOnlyChanged;
  final TextEditingController outputPathController;
  final VoidCallback onBrowseFolder;
  final ExportFormat selectedFormat;

  const ExportOptionsPanel({
    super.key,
    required this.projectId,
    required this.selectedLanguageIds,
    required this.onLanguageSelectionChanged,
    required this.validatedOnly,
    required this.onValidatedOnlyChanged,
    required this.outputPathController,
    required this.onBrowseFolder,
    required this.selectedFormat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Languages selection
        _buildFieldLabel('Languages to Export', theme),
        const SizedBox(height: 8),
        FutureBuilder(
          future: projectLangRepo.getByProject(projectId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const CircularProgressIndicator();
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return Text('Error loading languages: ${snapshot.error}');
            }

            final result = snapshot.data!;
            if (result.isErr) {
              return Text('Error: ${result.error}');
            }

            final projectLanguages = result.unwrap();
            return _buildLanguagesList(projectLanguages, theme, ref);
          },
        ),
        const SizedBox(height: 16),

        // Validated only option
        _buildValidatedOnlyCheckbox(theme),
        const SizedBox(height: 16),

        // Output path
        _buildFieldLabel('Output Folder', theme),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FluentTextField(
                controller: outputPathController,
                decoration: InputDecoration(
                  hintText: 'Select output folder',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                readOnly: true,
              ),
            ),
            const SizedBox(width: 8),
            _FluentIconButton(
              icon: FluentIcons.folder_open_24_regular,
              onTap: onBrowseFolder,
              tooltip: 'Browse',
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildFormatHint(theme),
      ],
    );
  }

  Widget _buildFieldLabel(String label, ThemeData theme) {
    return Text(
      label,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildLanguagesList(
    List<ProjectLanguage> projectLanguages,
    ThemeData theme,
    WidgetRef ref,
  ) {
    final languagesAsync = ref.watch(allLanguagesProvider);

    return languagesAsync.when(
      data: (languages) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.3),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: projectLanguages.map((projLang) {
              final language = languages.firstWhere(
                (lang) => lang.id == projLang.languageId,
                orElse: () => Language(
                  id: projLang.languageId,
                  code: 'unknown',
                  name: 'Unknown',
                  nativeName: 'Unknown',
                ),
              );

              final isSelected = selectedLanguageIds.contains(projLang.languageId);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () => _toggleLanguage(projLang.languageId, isSelected),
                    child: Row(
                      children: [
                        FluentCheckbox(
                          value: isSelected,
                          onChanged: (value) => _toggleLanguage(
                            projLang.languageId,
                            !value,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            language.displayName,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        Text(
                          '${projLang.progressPercent.toStringAsFixed(1)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      },
      loading: () => const CircularProgressIndicator(),
      error: (err, stack) => Text('Error: $err'),
    );
  }

  void _toggleLanguage(String languageId, bool currentlySelected) {
    final newSelection = Set<String>.from(selectedLanguageIds);
    if (currentlySelected) {
      newSelection.remove(languageId);
    } else {
      newSelection.add(languageId);
    }
    onLanguageSelectionChanged(newSelection);
  }

  Widget _buildValidatedOnlyCheckbox(ThemeData theme) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => onValidatedOnlyChanged(!validatedOnly),
        child: Row(
          children: [
            FluentCheckbox(
              value: validatedOnly,
              onChanged: (value) => onValidatedOnlyChanged(value),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Export only validated translations',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Exclude draft and unvalidated translations from export',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormatHint(ThemeData theme) {
    String hint = '';
    switch (selectedFormat) {
      case ExportFormat.pack:
        hint = 'Files will be named: !!!!!!!!!!_{LANG}_projectname.pack';
        break;
      case ExportFormat.csv:
        hint = 'One CSV file per language with key, source, and translation columns';
        break;
      case ExportFormat.excel:
        hint = 'One Excel file with sheets for each language';
        break;
      case ExportFormat.tmx:
        hint = 'TMX 1.4b format compatible with CAT tools';
        break;
    }

    return Row(
      children: [
        Icon(
          FluentIcons.info_24_regular,
          size: 14,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            hint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

/// Fluent Design icon button for folder browsing
class _FluentIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  const _FluentIconButton({
    required this.icon,
    this.onTap,
    this.tooltip,
  });

  @override
  State<_FluentIconButton> createState() => _FluentIconButtonState();
}

class _FluentIconButtonState extends State<_FluentIconButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEnabled = widget.onTap != null;

    final button = MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _isHovered && isEnabled
                ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.2),
            ),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: isEnabled
                ? theme.colorScheme.onSurface
                : theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }
}
