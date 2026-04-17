import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;

import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_icon_button.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../../models/domain/project.dart';
import '../../../../models/domain/project_metadata.dart';
import '../../../../models/domain/project_language.dart';
import '../../../../providers/selected_game_provider.dart';
import '../../../projects/providers/projects_screen_providers.dart';
import '../../../../providers/shared/service_providers.dart';
import '../../../../services/projects/i_project_initialization_service.dart'
    show InitializationLogMessage, InitializationLogLevel;
import '../../providers/game_translation_providers.dart';
import 'game_translation_creation_state.dart';
import 'step_select_source.dart';
import 'step_select_targets.dart';

/// Create game translation wizard dialog.
///
/// Two-step wizard for creating game translation projects:
/// 1. Select source pack (local_xx.pack)
/// 2. Select target languages
///
/// Retokenised (Plan 5d · Task 5): panel/accent/border tokens, `_StepHeader`
/// step indicator, [SmallTextButton] footer actions, [SmallIconButton] close.
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
      final projectName =
          '${selectedGame.name} - Game Translation ($languageSuffix)';

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

        final initService = ref.read(projectInitializationServiceProvider);

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
    final tokens = context.tokens;

    return Dialog(
      backgroundColor: tokens.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusMd),
        side: BorderSide(color: tokens.border),
      ),
      child: Container(
        width: 600,
        constraints: const BoxConstraints(maxHeight: 700),
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
                          _buildStepHeader(tokens),
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
            FluentIcons.globe_24_regular,
            size: 22,
            color: tokens.accent,
          ),
          const SizedBox(width: 12),
          Text(
            'Create Game Translation',
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          SmallIconButton(
            icon: FluentIcons.dismiss_24_regular,
            tooltip: 'Close',
            onTap: _isLoading ? () {} : () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// Step header: monospace step counter + display-font title, with a bottom
  /// divider. Kept inline per Plan 5d §10 (YAGNI — one caller today).
  Widget _buildStepHeader(TwmtThemeTokens tokens) {
    return Container(
      padding: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'STEP ${_currentStep + 1}/2',
            style: tokens.fontMono.copyWith(
              fontSize: 10,
              color: tokens.textDim,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _currentStep == 0
                ? 'Select source pack'
                : 'Select target languages',
            style: tokens.fontDisplay.copyWith(
              fontSize: 18,
              color: tokens.text,
              fontStyle: tokens.fontDisplayItalic
                  ? FontStyle.italic
                  : FontStyle.normal,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
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
            _progressMessage ?? 'Processing...',
            style: tokens.fontBody.copyWith(
              fontSize: 13,
              color: tokens.text,
            ),
          ),
          if (_importLogs.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 200,
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
                  return Text(
                    log.message,
                    style: tokens.fontMono.copyWith(
                      fontSize: 11.5,
                      color: log.level == InitializationLogLevel.error
                          ? tokens.err
                          : tokens.textDim,
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
          if (_currentStep > 0)
            SmallTextButton(
              label: 'Back',
              icon: FluentIcons.arrow_left_24_regular,
              onTap: _isLoading ? null : _previousStep,
            ),
          const Spacer(),
          SmallTextButton(
            label: 'Cancel',
            onTap: _isLoading ? null : () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          SmallTextButton(
            label: _currentStep == 0 ? 'Next' : 'Create',
            icon: _currentStep == 0
                ? FluentIcons.arrow_right_24_regular
                : FluentIcons.play_24_regular,
            onTap: _isLoading ? null : _nextStep,
          ),
        ],
      ),
    );
  }
}
