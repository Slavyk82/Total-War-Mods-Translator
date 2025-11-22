import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../models/domain/project.dart';
import '../../../../models/domain/project_metadata.dart';
import '../../../../models/domain/project_language.dart';
import '../../../../models/domain/detected_mod.dart';
import '../../providers/projects_screen_providers.dart';
import '../../../../services/service_locator.dart';
import '../../../../services/projects/i_project_initialization_service.dart';
import '../../../../services/settings/settings_service.dart';
import 'project_creation_state.dart';
import 'step_basic_info.dart';
import 'step_languages.dart';
import 'step_settings.dart';

/// Create project wizard dialog following Fluent Design patterns.
///
/// Multi-step wizard coordinator for creating new translation projects:
/// 1. Basic info (name, game, source file) - skipped if [detectedMod] provided
/// 2. Target languages selection
/// 3. Translation settings (batch size, parallel batches, custom prompt)
///
/// If [detectedMod] is provided, step 1 is auto-filled and skipped.
class CreateProjectDialog extends ConsumerStatefulWidget {
  final DetectedMod? detectedMod;

  const CreateProjectDialog({super.key, this.detectedMod});

  @override
  ConsumerState<CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends ConsumerState<CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _currentStep;
  late ProjectCreationState _state;

  bool _isLoading = false;
  String? _errorMessage;
  String? _progressMessage;
  final List<InitializationLogMessage> _importLogs = [];
  final ScrollController _logScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _state = ProjectCreationState(detectedMod: widget.detectedMod);
    // Skip Basic Info step if mod is provided (all fields auto-filled)
    _currentStep = widget.detectedMod != null ? 1 : 0;
  }

  @override
  void dispose() {
    _state.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      if (_validateCurrentStep()) {
        setState(() => _currentStep++);
      }
    } else {
      _createProject();
    }
  }

  void _previousStep() {
    final minStep = widget.detectedMod != null ? 1 : 0;
    if (_currentStep > minStep) {
      setState(() => _currentStep--);
    }
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) {
        return false;
      }
      if (_state.selectedGameId == null) {
        setState(() => _errorMessage = 'Please select a game installation');
        return false;
      }
    } else if (_currentStep == 1) {
      if (_state.selectedLanguageIds.isEmpty) {
        setState(() => _errorMessage = 'Please select at least one target language');
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
    });

    try {
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectLangRepo = ref.read(projectLanguageRepositoryProvider);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const uuid = Uuid();

      final projectId = uuid.v4();

      // Ensure game is selected
      String? gameId = _state.selectedGameId;

      // Wait for games to load
      final games = await ref.read(allGameInstallationsProvider.future);

      if (gameId == null && widget.detectedMod != null && _state.workshopMod != null) {
        // Find game by appId if not already selected
        final matchingGame = games.firstWhere(
          (game) =>
              game.steamAppId != null &&
              int.tryParse(game.steamAppId!) == _state.workshopMod!.appId,
          orElse: () => games.isNotEmpty
              ? games.first
              : throw StateError('No games found'),
        );
        gameId = matchingGame.id;
      }

      if (gameId == null) {
        throw Exception('Game installation must be selected');
      }

      // Get game installation to determine output folder
      final gameInstallation = games.firstWhere(
        (g) => g.id == gameId,
      );

      // Determine output folder (always game's data folder)
      String? outputFolder;
      if (gameInstallation.installationPath != null) {
        outputFolder = path.join(gameInstallation.installationPath!, 'data');
      } else {
        throw Exception('Game installation path is not configured');
      }

      // Create metadata with the project name as mod title
      final projectName = _state.nameController.text.trim();
      final metadata = ProjectMetadata(modTitle: projectName);

      final project = Project(
        id: projectId,
        name: projectName,
        modSteamId: _state.modSteamIdController.text.trim().isEmpty
            ? null
            : _state.modSteamIdController.text.trim(),
        gameInstallationId: gameId,
        sourceFilePath: _state.sourceFileController.text.trim().isEmpty
            ? null
            : _state.sourceFileController.text.trim(),
        outputFilePath: outputFolder,
        status: ProjectStatus.draft,
        batchSize: int.tryParse(_state.batchSizeController.text) ?? 25,
        parallelBatches: int.tryParse(_state.parallelBatchesController.text) ?? 3,
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

      // Initialize project: extract and import .loc files if source file exists
      if (project.sourceFilePath != null && project.sourceFilePath!.isNotEmpty) {
        await _initializeProjectFiles(projectId, project.sourceFilePath!);
        if (!mounted) return;
      } else {
        if (!mounted) return;
        // Show success without import
        FluentToast.success(context, 'Project created successfully');
      }

      if (!mounted) return;

      // Refresh projects list
      ref.invalidate(projectsWithDetailsProvider);

      // Close dialog with project ID
      Navigator.of(context).pop(projectId);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to create project: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeProjectFiles(String projectId, String packFilePath) async {
    if (!mounted) return;

    // Validate RPFM schema path is configured
    final settingsService = ServiceLocator.get<SettingsService>();
    final schemaPath = await settingsService.getString('rpfm_schema_path');

    if (schemaPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'RPFM schema path is not configured.\n\n'
            'Please configure it in Settings > RPFM Tool before creating a project.\n\n'
            'The schema path is required to extract localization files from .pack files.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _progressMessage = 'Extracting and importing localization files...';
      _importLogs.clear();
    });

    final initService = ServiceLocator.get<IProjectInitializationService>();

    // Listen to log stream
    final logSubscription = initService.logStream.listen((logMessage) {
      if (mounted) {
        setState(() {
          _importLogs.add(logMessage);
        });
        // Auto-scroll to bottom after setState completes
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && _logScrollController.hasClients) {
            _logScrollController.jumpTo(
              _logScrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });

    final initResult = await initService.initializeProject(
      projectId: projectId,
      packFilePath: packFilePath,
    );

    // Cancel log subscription
    await logSubscription.cancel();

    if (initResult.isErr) {
      if (!mounted) return;
      setState(() {
        _progressMessage = null;
        _errorMessage = 'Project created but failed to import translations: ${initResult.error}';
        _isLoading = false;
      });
      return;
    }

    final unitsCount = initResult.value;
    if (!mounted) return;

    // Show success with import count
    FluentToast.success(
      context,
      'Project created with $unitsCount translation units',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          const Text('Create New Project'),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress indicator
            _WizardStepIndicator(
              currentStep: _currentStep,
              hasDetectedMod: widget.detectedMod != null,
            ),
            const SizedBox(height: 24),

            // Progress message
            if (_progressMessage != null) ...[
              _ProgressBanner(
                message: _progressMessage!,
                logs: _importLogs,
                logScrollController: _logScrollController,
              ),
              const SizedBox(height: 16),
            ],

            // Error message
            if (_errorMessage != null && _progressMessage == null) ...[
              _ErrorBanner(message: _errorMessage!),
              const SizedBox(height: 16),
            ],

            // Step content
            Flexible(
              child: SingleChildScrollView(
                child: _buildStepContent(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        // Cancel button
        FluentDialogButton(
          icon: FluentIcons.dismiss_24_regular,
          label: 'Cancel',
          onTap: _isLoading ? null : () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),

        // Back button (only if not at initial step)
        if (_currentStep > (widget.detectedMod != null ? 1 : 0)) ...[
          FluentDialogButton(
            icon: FluentIcons.arrow_left_24_regular,
            label: 'Back',
            onTap: _isLoading ? null : _previousStep,
          ),
          const SizedBox(width: 8),
        ],

        // Next/Create button
        FluentDialogButton(
          icon: _currentStep < 2
              ? FluentIcons.arrow_right_24_regular
              : FluentIcons.checkmark_24_regular,
          label: _currentStep < 2 ? 'Next' : 'Create Project',
          isPrimary: true,
          isLoading: _isLoading,
          onTap: _isLoading ? null : _nextStep,
        ),
      ],
    );
  }

  Widget _buildStepContent() {
    return switch (_currentStep) {
      0 => StepBasicInfo(state: _state, formKey: _formKey),
      1 => StepLanguages(state: _state),
      2 => StepSettings(state: _state),
      _ => const SizedBox.shrink(),
    };
  }
}

/// Wizard step progress indicator.
class _WizardStepIndicator extends StatelessWidget {
  final int currentStep;
  final bool hasDetectedMod;

  const _WizardStepIndicator({
    required this.currentStep,
    required this.hasDetectedMod,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        _StepDot(step: 0, label: 'Basic Info', currentStep: currentStep, theme: theme),
        Expanded(child: _StepLine(step: 0, currentStep: currentStep, theme: theme)),
        _StepDot(step: 1, label: 'Languages', currentStep: currentStep, theme: theme),
        Expanded(child: _StepLine(step: 1, currentStep: currentStep, theme: theme)),
        _StepDot(step: 2, label: 'Settings', currentStep: currentStep, theme: theme),
      ],
    );
  }
}

/// Individual step indicator dot.
class _StepDot extends StatelessWidget {
  final int step;
  final String label;
  final int currentStep;
  final ThemeData theme;

  const _StepDot({
    required this.step,
    required this.label,
    required this.currentStep,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = currentStep == step;
    final isCompleted = currentStep > step;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isCompleted || isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: isCompleted
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
                          : theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.w600,
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
                : theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

/// Line connecting step dots.
class _StepLine extends StatelessWidget {
  final int step;
  final int currentStep;
  final ThemeData theme;

  const _StepLine({
    required this.step,
    required this.currentStep,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = currentStep > step;

    return Container(
      height: 2,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: isCompleted
          ? theme.colorScheme.primary
          : theme.colorScheme.surfaceContainerHighest,
    );
  }
}

/// Progress banner with logs.
class _ProgressBanner extends StatelessWidget {
  final String message;
  final List<InitializationLogMessage> logs;
  final ScrollController logScrollController;

  const _ProgressBanner({
    required this.message,
    required this.logs,
    required this.logScrollController,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: theme.colorScheme.primary,
          ),

          // Import logs
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 240,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: ListView.builder(
                  controller: logScrollController,
                  padding: EdgeInsets.zero,
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return _LogEntry(log: logs[index]);
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Individual log entry.
class _LogEntry extends StatelessWidget {
  final InitializationLogMessage log;

  const _LogEntry({required this.log});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? logColor;
    IconData? logIcon;

    // Only show icons for warnings and errors
    if (log.level == InitializationLogLevel.warning) {
      logColor = Colors.orange;
      logIcon = FluentIcons.warning_24_regular;
    } else if (log.level == InitializationLogLevel.error) {
      logColor = theme.colorScheme.error;
      logIcon = FluentIcons.error_circle_24_regular;
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 2, bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (logIcon != null) ...[
            Icon(
              logIcon,
              size: 14,
              color: logColor,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              log.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: log.level == InitializationLogLevel.error
                    ? theme.colorScheme.error
                    : (log.level == InitializationLogLevel.warning
                        ? Colors.orange
                        : theme.colorScheme.onSurface.withValues(alpha: 0.8)),
                fontSize: 12,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Error banner.
class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
