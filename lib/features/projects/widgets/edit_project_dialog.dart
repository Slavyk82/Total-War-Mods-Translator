import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../../../widgets/fluent/fluent_widgets.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/language.dart';
import '../../../models/domain/game_installation.dart';
import '../providers/projects_screen_providers.dart';

/// Edit project dialog following Fluent Design patterns.
///
/// Allows editing existing project properties:
/// - Basic info (name, game, file paths)
/// - Target languages (add/remove)
/// - Translation settings (batch size, parallel batches, custom prompt)
/// - Project status
class EditProjectDialog extends ConsumerStatefulWidget {
  final String projectId;

  const EditProjectDialog({
    super.key,
    required this.projectId,
  });

  @override
  ConsumerState<EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends ConsumerState<EditProjectDialog> {
  final _formKey = GlobalKey<FormState>();

  // Form controllers
  final _nameController = TextEditingController();
  final _modSteamIdController = TextEditingController();
  final _sourceFileController = TextEditingController();
  final _outputFileController = TextEditingController();
  final _batchSizeController = TextEditingController();
  final _parallelBatchesController = TextEditingController();
  final _customPromptController = TextEditingController();

  String? _selectedGameId;
  final Set<String> _selectedLanguageIds = {};
  final Set<String> _originalLanguageIds = {};

  bool _isLoading = false;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      _loadProjectData();
      _isInitialized = true;
    }
  }

  Future<void> _loadProjectData() async {
    setState(() => _isLoading = true);

    try {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectLangRepo = ref.read(projectLanguageRepositoryProvider);

      // Load project
      final projectResult = await projectRepo.getById(widget.projectId);
      if (projectResult.isErr) {
        throw Exception('Project not found');
      }

      final project = projectResult.unwrap();

      // Load project languages
      final langResult = await projectLangRepo.getByProject(widget.projectId);
      final Set<String> languageIds = {};
      if (langResult.isOk) {
        for (final projLang in langResult.unwrap()) {
          languageIds.add(projLang.languageId);
        }
      }

      if (!mounted) return;

      setState(() {
        _nameController.text = project.name;
        _modSteamIdController.text = project.modSteamId ?? '';
        _sourceFileController.text = project.sourceFilePath ?? '';
        _outputFileController.text = project.outputFilePath ?? '';
        _batchSizeController.text = project.batchSize.toString();
        _parallelBatchesController.text = project.parallelBatches.toString();
        _customPromptController.text = project.customPrompt ?? '';
        _selectedGameId = project.gameInstallationId;
        _selectedLanguageIds.addAll(languageIds);
        _originalLanguageIds.addAll(languageIds);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load project: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _modSteamIdController.dispose();
    _sourceFileController.dispose();
    _outputFileController.dispose();
    _batchSizeController.dispose();
    _parallelBatchesController.dispose();
    _customPromptController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectLangRepo = ref.read(projectLanguageRepositoryProvider);

      // Load existing project
      final projectResult = await projectRepo.getById(widget.projectId);
      if (projectResult.isErr) {
        throw Exception('Project not found');
      }

      final existingProject = projectResult.unwrap();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Update project
      final updatedProject = existingProject.copyWith(
        name: _nameController.text.trim(),
        modSteamId: _modSteamIdController.text.trim().isEmpty
            ? null
            : _modSteamIdController.text.trim(),
        gameInstallationId: _selectedGameId,
        sourceFilePath: _sourceFileController.text.trim().isEmpty
            ? null
            : _sourceFileController.text.trim(),
        outputFilePath: _outputFileController.text.trim().isEmpty
            ? null
            : _outputFileController.text.trim(),
        batchSize: int.tryParse(_batchSizeController.text) ?? 25,
        parallelBatches: int.tryParse(_parallelBatchesController.text) ?? 3,
        customPrompt: _customPromptController.text.trim().isEmpty
            ? null
            : _customPromptController.text.trim(),
        updatedAt: now,
      );

      final updateResult = await projectRepo.update(updatedProject);
      if (updateResult.isErr) {
        throw Exception(updateResult.error);
      }

      // Handle language changes
      final languagesToAdd = _selectedLanguageIds.difference(_originalLanguageIds);
      final languagesToRemove = _originalLanguageIds.difference(_selectedLanguageIds);

      // Add new languages
      for (final languageId in languagesToAdd) {
        final projectLanguage = ProjectLanguage(
          id: const Uuid().v4(),
          projectId: widget.projectId,
          languageId: languageId,
          progressPercent: 0.0,
          createdAt: now,
          updatedAt: now,
        );
        await projectLangRepo.insert(projectLanguage);
      }

      // Remove languages
      if (languagesToRemove.isNotEmpty) {
        final existingLangsResult = await projectLangRepo.getByProject(widget.projectId);
        if (existingLangsResult.isOk) {
          for (final projLang in existingLangsResult.unwrap()) {
            if (languagesToRemove.contains(projLang.languageId)) {
              await projectLangRepo.delete(projLang.id);
            }
          }
        }
      }

      if (!mounted) return;

      // Refresh projects list
      ref.invalidate(projectsWithDetailsProvider);

      // Show success and close dialog
      FluentToast.success(context, 'Project updated successfully');
      Navigator.of(context).pop(true);

    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to update project: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _browseSourceFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pack', 'loc', 'tsv'],
      dialogTitle: 'Select source file',
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _sourceFileController.text = result.files.single.path!;
      });
    }
  }

  Future<void> _browseOutputFolder() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select output folder',
    );

    if (result != null) {
      setState(() {
        _outputFileController.text = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gamesAsync = ref.watch(allGameInstallationsProvider);
    final languagesAsync = ref.watch(allLanguagesProvider);

    if (_isLoading && !_isInitialized) {
      return AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: const SizedBox(
          width: 200,
          height: 100,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Row(
        children: [
          Icon(
            FluentIcons.edit_24_regular,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Text('Edit Project'),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Error message
                if (_errorMessage != null) ...[
                  _buildErrorBanner(theme),
                  const SizedBox(height: 16),
                ],

                // Project name
                _buildFieldLabel('Project Name', theme),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: 'Enter project name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Game selection
                _buildFieldLabel('Game', theme),
                const SizedBox(height: 8),
                gamesAsync.when(
                  data: (games) => _buildGameDropdown(games, theme),
                  loading: () => const CircularProgressIndicator(),
                  error: (err, stack) => Text('Error: $err'),
                ),
                const SizedBox(height: 16),

                // Steam Workshop ID
                _buildFieldLabel('Steam Workshop ID (Optional)', theme),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _modSteamIdController,
                  decoration: InputDecoration(
                    hintText: 'Enter Steam Workshop mod ID',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                // Source file
                _buildFieldLabel('Source File (Optional)', theme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FluentTextField(
                        controller: _sourceFileController,
                        decoration: InputDecoration(
                          hintText: 'Select source file',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        readOnly: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FluentIconButton(
                      icon: Icon(FluentIcons.folder_open_24_regular),
                      onPressed: _browseSourceFile,
                      tooltip: 'Browse',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Output folder
                _buildFieldLabel('Output Folder (Optional)', theme),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FluentTextField(
                        controller: _outputFileController,
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
                    FluentIconButton(
                      icon: Icon(FluentIcons.folder_open_24_regular),
                      onPressed: _browseOutputFolder,
                      tooltip: 'Browse',
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Languages
                _buildFieldLabel('Target Languages', theme),
                const SizedBox(height: 8),
                languagesAsync.when(
                  data: (languages) => _buildLanguagesList(languages, theme),
                  loading: () => const CircularProgressIndicator(),
                  error: (err, stack) => Text('Error: $err'),
                ),
                const SizedBox(height: 16),

                // Batch size
                _buildFieldLabel('Batch Size', theme),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _batchSizeController,
                  decoration: InputDecoration(
                    hintText: 'Number of units per batch',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                // Parallel batches
                _buildFieldLabel('Parallel Batches', theme),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _parallelBatchesController,
                  decoration: InputDecoration(
                    hintText: 'Number of parallel batches',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),

                // Custom prompt
                _buildFieldLabel('Custom Translation Prompt (Optional)', theme),
                const SizedBox(height: 8),
                FluentTextField(
                  controller: _customPromptController,
                  decoration: InputDecoration(
                    hintText: 'Enter custom instructions',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        FluentDialogButton(
          icon: FluentIcons.dismiss_24_regular,
          label: 'Cancel',
          onTap: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        FluentDialogButton(
          icon: FluentIcons.save_24_regular,
          label: 'Save Changes',
          isPrimary: true,
          isLoading: _isLoading,
          onTap: _isLoading ? null : _saveChanges,
        ),
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

  Widget _buildGameDropdown(List<GameInstallation> games, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedGameId,
          isExpanded: true,
          items: games.map((game) {
            return DropdownMenuItem(
              value: game.id,
              child: Text(game.gameName),
            );
          }).toList(),
          onChanged: (value) {
            setState(() => _selectedGameId = value);
          },
        ),
      ),
    );
  }

  Widget _buildLanguagesList(List<Language> languages, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: languages.where((lang) => lang.isActive).map((language) {
        final isSelected = _selectedLanguageIds.contains(language.id);
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
                  Text(language.displayName, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
