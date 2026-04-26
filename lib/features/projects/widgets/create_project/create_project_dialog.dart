import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';
import 'package:twmt/widgets/wizard/wizard_step_header.dart';

import 'package:twmt/features/settings/providers/settings_providers.dart'
    show SettingsKeys;

import '../../../../widgets/fluent/fluent_widgets.dart';
import '../../../../models/domain/project.dart';
import '../../../../models/domain/project_metadata.dart';
import '../../../../models/domain/project_language.dart';
import '../../../../models/domain/detected_mod.dart';
import '../../../../models/domain/language.dart';
import '../../../../repositories/language_repository.dart';
import '../../../../services/settings/settings_service.dart';
import '../../providers/projects_screen_providers.dart';
import '../../../../providers/shared/service_providers.dart';
import '../../../../services/glossary/glossary_auto_provisioning_service.dart';
import '../../../../services/projects/i_project_initialization_service.dart';
import '../../../../services/service_locator.dart';
import 'project_creation_state.dart';
import 'step_basic_info.dart';
import 'step_settings.dart';

/// Resolves the target language to use when auto-creating a project language.
///
/// Tries the user's default target language from settings first. If that
/// language is missing or inactive, falls back to the first active language.
/// Throws an [Exception] with a user-actionable message when no active
/// language is available at all — the caller's `try/catch` surfaces the
/// message in the dialog's error banner.
///
/// Exposed at the top level (rather than as a private dialog method) so it
/// can be exercised by lightweight unit tests without pumping the full
/// wizard widget tree.
Future<Language> resolveDefaultTargetLanguage(
  SettingsService settings,
  LanguageRepository langRepo,
) async {
  final defaultCode = await settings.getString(
    SettingsKeys.defaultTargetLanguage,
    defaultValue: SettingsKeys.defaultTargetLanguageValue,
  );
  final byCode = await langRepo.getByCode(defaultCode);
  if (byCode.isOk && byCode.unwrap().isActive) {
    return byCode.unwrap();
  }
  final active = await langRepo.getActive();
  if (active.isErr || active.unwrap().isEmpty) {
    throw Exception(
      'No active target language. Configure a default target language in '
      'Settings > General, or activate at least one language.',
    );
  }
  return active.unwrap().first;
}

/// Create project wizard dialog.
///
/// Two-step wizard coordinator for creating new translation projects:
/// 1. Basic info (name, game, source file) - skipped if [detectedMod] provided
/// 2. Translation settings (batch size, parallel batches, custom prompt)
///
/// The target language is resolved automatically at creation time from the
/// user's default target language setting (with fallback to the first active
/// language). See [_createProject].
///
/// If [detectedMod] is provided, step 1 is auto-filled and skipped.
///
/// Retokenised (Plan 5d · Task 6): panel/accent/border tokens, [WizardStepHeader]
/// step indicator, [SmallTextButton] footer actions, [SmallIconButton] close.
class CreateProjectDialog extends ConsumerStatefulWidget {
  final DetectedMod? detectedMod;

  const CreateProjectDialog({super.key, this.detectedMod});

  @override
  ConsumerState<CreateProjectDialog> createState() =>
      _CreateProjectDialogState();
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

  int get _minStep => widget.detectedMod != null ? 1 : 0;

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
    if (_currentStep > _minStep) {
      setState(() => _currentStep--);
    }
  }

  bool _validateCurrentStep() {
    if (_currentStep == 0) {
      if (!_formKey.currentState!.validate()) return false;
      if (_state.selectedGameId == null) {
        setState(() => _errorMessage = t.projects.createProject.errors.selectGame);
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

      if (gameId == null &&
          widget.detectedMod != null &&
          _state.workshopMod != null) {
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
        throw Exception(t.projects.createProject.errors.gameMustBeSelected);
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
        throw Exception(t.projects.createProject.errors.gamePathNotConfigured);
      }

      // Create metadata with the project name as mod title
      final projectName = _state.nameController.text.trim();
      final metadata = ProjectMetadata(
        modTitle: projectName,
        modImageUrl: _state.detectedMod?.imageUrl,
      );

      // Resolve the default target language BEFORE inserting the project row.
      // The resolver can throw (no active language) and we do not want a
      // half-created project with no project_language row lingering in the
      // database if that happens.
      final settings = ref.read(settingsServiceProvider);
      final langRepo = ref.read(languageRepositoryProvider);
      final target = await resolveDefaultTargetLanguage(settings, langRepo);

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

      final projectLanguage = ProjectLanguage(
        id: uuid.v4(),
        projectId: projectId,
        languageId: target.id,
        progressPercent: 0.0,
        createdAt: now,
        updatedAt: now,
      );
      await projectLangRepo.insert(projectLanguage);

      // Best-effort: provision an empty glossary for the new project's target
      // language. Internally error-swallowed — never blocks project creation.
      await ServiceLocator.get<GlossaryAutoProvisioningService>()
          .provisionForProject(
        projectId: projectId,
        targetLanguageIds: [target.id],
      );

      // Initialize project: extract and import .loc files if source file exists
      if (project.sourceFilePath != null &&
          project.sourceFilePath!.isNotEmpty) {
        await _initializeProjectFiles(projectId, project.sourceFilePath!);
        if (!mounted) return;
      } else {
        if (!mounted) return;
        // Show success without import
        FluentToast.success(context, t.projects.messages.projectCreated);
      }

      if (!mounted) return;

      // Refresh projects list
      ref.invalidate(projectsWithDetailsProvider);

      // Close dialog with project ID
      Navigator.of(context).pop(projectId);
    } catch (e) {
      setState(() {
        _errorMessage = t.projects.messages.createFailed(error: e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _initializeProjectFiles(
      String projectId, String packFilePath) async {
    if (!mounted) return;

    // Validate RPFM schema path is configured
    final settingsService = ref.read(settingsServiceProvider);
    final schemaPath = await settingsService.getString('rpfm_schema_path');

    if (schemaPath.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = t.projects.createProject.errors.rpfmSchemaNotConfigured;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _progressMessage = t.projects.createProject.progress.extracting;
      _importLogs.clear();
    });

    final initService = ref.read(projectInitializationServiceProvider);

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
        _errorMessage =
            t.projects.messages.importFailed(error: initResult.error.toString());
        _isLoading = false;
      });
      return;
    }

    final unitsCount = initResult.value;
    if (!mounted) return;

    // Show success with import count
    FluentToast.success(
      context,
      t.projects.messages.projectCreatedUnits(count: unitsCount),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;

    return Dialog(
      backgroundColor: tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            _buildHeader(tokens),
            // Content
            Flexible(
              child: _isLoading
                  ? _buildProgress(tokens)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Step header (Plan 5d §7 pattern)
                          WizardStepHeader(
                            stepNumber: _currentStep + 1,
                            totalSteps: 2,
                            title: [
                              t.projects.createProject.steps.basicInfo,
                              t.projects.createProject.steps.translationSettings,
                            ][_currentStep],
                          ),
                          const SizedBox(height: 20),
                          // Step content
                          _buildStepContent(),
                          // Error message
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 16),
                            _buildError(tokens),
                          ],
                        ],
                      ),
                    ),
            ),
            // Footer
            if (!_isLoading) _buildFooter(tokens),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: tokens.border),
        ),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.add_circle_24_regular,
            size: 22,
            color: tokens.accent,
          ),
          const SizedBox(width: 12),
          Text(
            t.projects.createProject.title,
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayStyle,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          if (!_isLoading)
            SmallIconButton(
              icon: FluentIcons.dismiss_24_regular,
              tooltip: t.common.actions.close,
              onTap: () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    return switch (_currentStep) {
      0 => StepBasicInfo(state: _state, formKey: _formKey),
      1 => StepSettings(state: _state),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _buildError(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.errBg,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: tokens.err.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            FluentIcons.error_circle_24_regular,
            color: tokens.err,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
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

  Widget _buildProgress(TwmtThemeTokens tokens) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _progressMessage ?? t.projects.createProject.progress.processing,
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
            ),
          ),
          if (_importLogs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 240,
              decoration: BoxDecoration(
                color: tokens.panel2,
                borderRadius: BorderRadius.circular(tokens.radiusSm),
                border: Border.all(color: tokens.border),
              ),
              child: ListView.builder(
                controller: _logScrollController,
                padding: const EdgeInsets.all(8),
                itemCount: _importLogs.length,
                itemBuilder: (context, index) {
                  final log = _importLogs[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (log.level == InitializationLogLevel.warning ||
                            log.level == InitializationLogLevel.error) ...[
                          Icon(
                            log.level == InitializationLogLevel.error
                                ? FluentIcons.error_circle_24_regular
                                : FluentIcons.warning_24_regular,
                            size: 12,
                            color: log.level == InitializationLogLevel.error
                                ? tokens.err
                                : tokens.warn,
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            log.message,
                            style: tokens.fontMono.copyWith(
                              fontSize: 11.5,
                              color: log.level == InitializationLogLevel.error
                                  ? tokens.err
                                  : (log.level ==
                                          InitializationLogLevel.warning
                                      ? tokens.warn
                                      : tokens.textDim),
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildFooter(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: tokens.border),
        ),
      ),
      child: Row(
        children: [
          if (_currentStep > _minStep)
            SmallTextButton(
              label: t.common.actions.back,
              icon: FluentIcons.arrow_left_24_regular,
              onTap: _isLoading ? null : _previousStep,
            ),
          const Spacer(),
          SmallTextButton(
            label: t.common.actions.cancel,
            onTap: _isLoading ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          SmallTextButton(
            label: _currentStep < 1 ? t.projects.createProject.actions.next : t.projects.createProject.actions.create,
            icon: _currentStep < 1
                ? FluentIcons.arrow_right_24_regular
                : FluentIcons.play_24_regular,
            onTap: _isLoading ? null : _nextStep,
          ),
        ],
      ),
    );
  }
}
