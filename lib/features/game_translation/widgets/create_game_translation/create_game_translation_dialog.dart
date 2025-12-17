import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../models/domain/project.dart';
import '../../../../models/domain/project_metadata.dart';
import '../../../../models/domain/project_language.dart';
import '../../../../providers/selected_game_provider.dart';
import '../../../projects/providers/projects_screen_providers.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/projects/i_project_initialization_service.dart'
    show IProjectInitializationService, InitializationLogMessage, InitializationLogLevel;
import '../../providers/game_translation_providers.dart';
import 'game_translation_creation_state.dart';
import 'step_select_source.dart';
import 'step_select_targets.dart';

/// Create game translation wizard dialog following Fluent Design patterns.
///
/// Two-step wizard for creating game translation projects:
/// 1. Select source pack (local_xx.pack)
/// 2. Select target languages
class CreateGameTranslationDialog extends ConsumerStatefulWidget {
  const CreateGameTranslationDialog({super.key});

  @override
  ConsumerState<CreateGameTranslationDialog> createState() =>
      _CreateGameTranslationDialogState();
}

class _CreateGameTranslationDialogState
    extends ConsumerState<CreateGameTranslationDialog> {
  int _currentStep = 0;
  final _state = GameTranslationCreationState();

  bool _isLoading = false;
  String? _errorMessage;
  String? _progressMessage;
  final List<InitializationLogMessage> _importLogs = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void dispose() {
    _state.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 1) {
      if (_validateCurrentStep()) {
        setState(() => _currentStep++);
      }
    } else {
      _createProject();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    }
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      if (_state.selectedSourcePack == null) {
        setState(
            () => _errorMessage = 'Please select a source localization pack');
        return false;
      }
    } else if (_currentStep == 1) {
      if (_state.selectedLanguageIds.isEmpty) {
        setState(
            () => _errorMessage = 'Please select at least one target language');
        return false;
      }
    }
    setState(() => _errorMessage = null);
    return true;
  }

  Future<void> _createProject() async {
    if (!_validateCurrentStep()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _progressMessage = 'Creating project...';
    });

    try {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectLangRepo = ref.read(projectLanguageRepositoryProvider);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const uuid = Uuid();

      final projectId = uuid.v4();

      // Get selected game installation
      final selectedGame = await ref.read(selectedGameProvider.future);
      if (selectedGame == null) {
        throw Exception('No game selected');
      }

      final games = await ref.read(allGameInstallationsProvider.future);
      final gameInstallation = games.firstWhere(
        (g) => g.gameCode == selectedGame.code,
        orElse: () => throw Exception('Game installation not found'),
      );

      // Determine output folder (game's data folder)
      String? outputFolder;
      if (gameInstallation.installationPath != null) {
        outputFolder = path.join(gameInstallation.installationPath!, 'data');
      } else {
        throw Exception('Game installation path is not configured');
      }

      // Get target language names for the project name
      final langRepo = ref.read(languageRepositoryProvider);
      final targetLanguageNames = <String>[];
      for (final langId in _state.selectedLanguageIds) {
        final langResult = await langRepo.getById(langId);
        if (langResult.isOk) {
          targetLanguageNames.add(langResult.unwrap().name);
        }
      }

      // Create project name from game name and target languages
      final sourcePack = _state.selectedSourcePack!;
      final languageSuffix = targetLanguageNames.isNotEmpty
          ? targetLanguageNames.join(', ')
          : 'Translation';
      final projectName = '${selectedGame.name} - Game Translation ($languageSuffix)';

      // Create metadata
      final metadata = ProjectMetadata(modTitle: projectName);

      final project = Project(
        id: projectId,
        name: projectName,
        projectType: 'game',
        sourceLanguageCode: sourcePack.languageCode,
        gameInstallationId: gameInstallation.id,
        sourceFilePath: sourcePack.packFilePath,
        outputFilePath: outputFolder,
        batchSize: int.tryParse(_state.batchSizeController.text) ?? 25,
        parallelBatches:
            int.tryParse(_state.parallelBatchesController.text) ?? 3,
        customPrompt: _state.customPromptController.text.trim().isEmpty
            ? null
            : _state.customPromptController.text.trim(),
        createdAt: now,
        updatedAt: now,
        metadata: metadata.toJsonString(),
      );

      // Create project
      final result = await projectRepo.insert(project);

      if (result.isErr) {
        throw Exception(result.error);
      }

      // Create project languages
      for (final languageId in _state.selectedLanguageIds) {
        final projectLanguage = ProjectLanguage(
          id: uuid.v4(),
          projectId: projectId,
          languageId: languageId,
          progressPercent: 0.0,
          createdAt: now,
          updatedAt: now,
        );

        await projectLangRepo.insert(projectLanguage);
      }

      // Initialize project (extract localization files)
      if (project.hasSourceFile) {
        setState(() {
          _progressMessage = 'Extracting localization files...';
          _importLogs.clear();
        });

        final initService =
            ServiceLocator.get<IProjectInitializationService>();

        // Listen to progress and log streams
        final progressSub = initService.progressStream.listen((progress) {
          if (mounted) {
            setState(() {
              _progressMessage =
                  'Extracting... ${(progress * 100).toStringAsFixed(0)}%';
            });
          }
        });

        final logSub = initService.logStream.listen((message) {
          if (mounted) {
            setState(() {
              _importLogs.add(message);
            });
            _scrollToBottom();
          }
        });

        try {
          await initService.initializeProject(
            projectId: project.id,
            packFilePath: project.sourceFilePath!,
          );
        } finally {
          await progressSub.cancel();
          await logSub.cancel();
        }
      }

      // Refresh providers
      ref.invalidate(gameTranslationProjectsProvider);

      if (mounted) {
        Navigator.of(context).pop(projectId);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
          _progressMessage = null;
        });
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(theme),
            // Content
            Flexible(
              child: _isLoading
                  ? _buildProgress(theme)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step indicator
                          _buildStepIndicator(theme),
                          const SizedBox(height: 24),
                          // Step content
                          _buildStepContent(),
                          // Error message
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _buildError(theme),
                          ],
                        ],
                      ),
                    ),
            ),
            // Footer
            if (!_isLoading) _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.globe_24_regular,
            size: 28,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Text(
            'Create Game Translation',
            style: theme.textTheme.titleLarge,
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(FluentIcons.dismiss_24_regular),
            onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(ThemeData theme) {
    return Row(
      children: [
        _buildStepDot(theme, 0, 'Source'),
        Expanded(
          child: Container(
            height: 2,
            color: _currentStep >= 1
                ? theme.colorScheme.primary
                : theme.dividerColor,
          ),
        ),
        _buildStepDot(theme, 1, 'Languages'),
      ],
    );
  }

  Widget _buildStepDot(ThemeData theme, int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color:
                isActive ? theme.colorScheme.primary : theme.colorScheme.surface,
            border: Border.all(
              color: isActive
                  ? theme.colorScheme.primary
                  : theme.dividerColor,
              width: 2,
            ),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? Icon(
                    FluentIcons.checkmark_24_regular,
                    size: 16,
                    color: theme.colorScheme.onPrimary,
                  )
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      color: isActive
                          ? theme.colorScheme.onPrimary
                          : theme.textTheme.bodyMedium?.color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: isActive
                ? theme.colorScheme.primary
                : theme.textTheme.bodySmall?.color,
            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case 0:
        return StepSelectSource(
          state: _state,
          onStateChanged: () => setState(() {}),
        );
      case 1:
        return StepSelectTargets(
          state: _state,
          onStateChanged: () => setState(() {}),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildError(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.error.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: theme.colorScheme.error,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            _progressMessage ?? 'Processing...',
            style: theme.textTheme.bodyMedium,
          ),
          if (_importLogs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor),
              ),
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: _importLogs.length,
                itemBuilder: (context, index) {
                  final log = _importLogs[index];
                  return Text(
                    log.message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: log.level == InitializationLogLevel.error
                          ? theme.colorScheme.error
                          : theme.textTheme.bodySmall?.color,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFooter(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (_currentStep > 0)
            FluentButton(
              onPressed: _previousStep,
              icon: const Icon(FluentIcons.arrow_left_24_regular),
              child: const Text('Back'),
            )
          else
            const SizedBox.shrink(),
          Row(
            children: [
              FluentButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 8),
              FluentButton(
                onPressed: _nextStep,
                child: Text(_currentStep == 1 ? 'Create' : 'Next'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
