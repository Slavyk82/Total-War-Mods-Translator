import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../../models/domain/compilation.dart';
import '../../../repositories/compilation_repository.dart';
import '../../../repositories/game_installation_repository.dart';
import '../../../repositories/language_repository.dart';
import '../../../repositories/project_repository.dart';
import '../../../services/file/i_loc_file_service.dart';
import '../../../services/file/i_pack_image_generator_service.dart';
import '../../../services/file/pack_export_utils.dart';
import '../../../services/rpfm/i_rpfm_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';
import '../models/compilation_editor_state.dart';
import '../models/compilation_with_details.dart';

/// Notifier for compilation editor state management.
///
/// Handles all operations for creating, editing, and generating
/// pack compilations including form state, validation, and pack generation.
class CompilationEditorNotifier extends Notifier<CompilationEditorState> {
  @override
  CompilationEditorState build() => const CompilationEditorState();

  void reset() {
    state = const CompilationEditorState();
  }

  void loadCompilation(CompilationWithDetails details) {
    state = CompilationEditorState(
      compilationId: details.compilation.id,
      name: details.compilation.name,
      prefix: details.compilation.prefix,
      packName: details.compilation.packName,
      selectedLanguageId: details.compilation.languageId,
      selectedProjectIds: details.projects.map((p) => p.id).toSet(),
    );
  }

  void updateName(String name) {
    state = state.copyWith(name: name);
  }

  void updatePrefix(String prefix) {
    state = state.copyWith(prefix: prefix);
  }

  void updatePackName(String packName) {
    state = state.copyWith(packName: packName);
  }

  Future<void> updateLanguage(String? languageId) async {
    if (languageId == null) {
      state = state.copyWith(
        selectedLanguageId: languageId,
        prefix: '',
        selectedProjectIds: const {},
      );
      return;
    }

    // Fetch the language to get its code and update the prefix
    final langRepo = ServiceLocator.get<LanguageRepository>();
    final result = await langRepo.getById(languageId);

    String newPrefix = state.prefix;
    if (result.isOk) {
      final language = result.unwrap();
      newPrefix =
          CompilationEditorState.defaultPrefixForLanguage(language.code);
    }

    state = state.copyWith(
      selectedLanguageId: languageId,
      prefix: newPrefix,
      selectedProjectIds: const {},
    );
  }

  void toggleProject(String projectId) {
    final current = Set<String>.from(state.selectedProjectIds);
    if (current.contains(projectId)) {
      current.remove(projectId);
    } else {
      current.add(projectId);
    }
    state = state.copyWith(selectedProjectIds: current);
  }

  void selectAllProjects(List<String> projectIds) {
    state = state.copyWith(selectedProjectIds: projectIds.toSet());
  }

  void deselectAllProjects() {
    state = state.copyWith(selectedProjectIds: const {});
  }

  void clearMessages() {
    state = state.copyWith(errorMessage: null, successMessage: null);
  }

  void toggleGeneratePackImage() {
    state = state.copyWith(generatePackImage: !state.generatePackImage);
  }

  /// Request cancellation of the current compilation.
  /// This immediately kills any running RPFM process.
  Future<void> cancelCompilation() async {
    if (state.isCompiling) {
      state = state.copyWith(
        isCancelled: true,
        currentStep: 'Cancelling...',
      );
      // Immediately cancel the RPFM service to kill any running process
      final rpfmService = ServiceLocator.get<IRpfmService>();
      await rpfmService.cancel();
    }
  }

  Future<bool> saveCompilation(String gameInstallationId) async {
    if (!state.canSave) return false;

    final compilationRepo = ServiceLocator.get<CompilationRepository>();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    try {
      if (state.isEditing) {
        // Update existing compilation
        final existingResult =
            await compilationRepo.getById(state.compilationId!);
        if (existingResult.isErr) {
          state = state.copyWith(errorMessage: 'Compilation not found');
          return false;
        }

        final existing = existingResult.unwrap();
        final updated = existing.copyWith(
          name: state.name,
          prefix: state.prefix,
          packName: state.packName,
          gameInstallationId: gameInstallationId,
          languageId: state.selectedLanguageId,
          updatedAt: now,
        );

        final updateResult = await compilationRepo.update(updated);
        if (updateResult.isErr) {
          state =
              state.copyWith(errorMessage: updateResult.unwrapErr().message);
          return false;
        }

        // Update projects
        await compilationRepo.setProjects(
          state.compilationId!,
          state.selectedProjectIds.toList(),
        );
      } else {
        // Create new compilation
        final compilation = Compilation(
          id: const Uuid().v4(),
          name: state.name,
          prefix: state.prefix,
          packName: state.packName,
          gameInstallationId: gameInstallationId,
          languageId: state.selectedLanguageId,
          createdAt: now,
          updatedAt: now,
        );

        final insertResult = await compilationRepo.insert(compilation);
        if (insertResult.isErr) {
          state =
              state.copyWith(errorMessage: insertResult.unwrapErr().message);
          return false;
        }

        // Add projects
        await compilationRepo.setProjects(
          compilation.id,
          state.selectedProjectIds.toList(),
        );

        state = state.copyWith(compilationId: compilation.id);
      }

      state = state.copyWith(successMessage: 'Compilation saved');
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: e.toString());
      return false;
    }
  }

  Future<bool> generatePack(String gameInstallationId) async {
    if (!state.canCompile) return false;

    // First save if needed
    if (!state.isEditing) {
      final saved = await saveCompilation(gameInstallationId);
      if (!saved) return false;
    }

    final logger = ServiceLocator.get<LoggingService>();
    final locFileService = ServiceLocator.get<ILocFileService>();
    final rpfmService = ServiceLocator.get<IRpfmService>();
    final compilationRepo = ServiceLocator.get<CompilationRepository>();
    final projectRepo = ServiceLocator.get<ProjectRepository>();
    final gameRepo = ServiceLocator.get<GameInstallationRepository>();
    final langRepo = ServiceLocator.get<LanguageRepository>();
    final packUtils = PackExportUtils(logger: logger);

    state = state.copyWith(
      isCompiling: true,
      isCancelled: false,
      progress: 0.0,
      currentStep: 'Preparing...',
      errorMessage: null,
      successMessage: null,
    );

    logger.info('Starting pack compilation', {'compilationName': state.name});

    Directory? tempDir;

    try {
      // Get game installation for output path
      logger.info('Loading game installation...');
      final gameResult = await gameRepo.getById(gameInstallationId);
      if (gameResult.isErr) {
        throw Exception('Failed to load game installation');
      }
      final gameInstallation = gameResult.unwrap();
      final gameDataPath =
          path.join(gameInstallation.installationPath!, 'data');
      logger.info('Game data path: $gameDataPath');

      // Get language code for the selected language
      final langResult = await langRepo.getById(state.selectedLanguageId!);
      if (langResult.isErr) {
        throw Exception('Failed to load language');
      }
      final language = langResult.unwrap();
      logger
          .info('Target language: ${language.displayName} (${language.code})');

      // Create temp directory
      tempDir = await packUtils.createTempDirectory('twmt_compilation');
      logger.info('Created temp directory: ${tempDir.path}');

      final projectIds = state.selectedProjectIds.toList();
      var processedCount = 0;
      var totalFilesGenerated = 0;

      logger.info('Processing ${projectIds.length} projects...');

      // Process each project - only for the selected language
      for (final projectId in projectIds) {
        // Check for cancellation
        if (state.isCancelled) {
          logger.info('Pack compilation cancelled by user');
          state = state.copyWith(
            isCompiling: false,
            isCancelled: false,
            progress: 0.0,
            currentStep: null,
            errorMessage: 'Compilation cancelled',
          );
          return false;
        }

        final projectResult = await projectRepo.getById(projectId);
        if (projectResult.isErr) {
          logger.warning('Project not found: $projectId');
          continue;
        }

        final project = projectResult.unwrap();

        state = state.copyWith(
          currentStep:
              'Processing: ${project.displayName} (${processedCount + 1}/${projectIds.length})',
          progress: processedCount / projectIds.length * 0.8,
        );

        logger.info('Processing project: ${project.displayName}');

        // Generate TSV files for the selected language only
        final result = await locFileService.generateLocFilesGroupedBySource(
          projectId: projectId,
          languageCode: language.code,
          validatedOnly: false,
        );

        if (result.isOk) {
          final tsvPaths = result.unwrap();
          logger.info(
              'Generated ${tsvPaths.length} loc files for ${project.displayName}');
          totalFilesGenerated += tsvPaths.length;
          await packUtils.copyTsvFilesToPackStructure(tsvPaths, tempDir);
        } else {
          logger.warning(
              'Failed to generate loc files for ${project.displayName}');
        }

        processedCount++;
      }

      logger.info('Total loc files generated: $totalFilesGenerated');

      // Check for cancellation before pack creation
      if (state.isCancelled) {
        logger.info('Pack compilation cancelled by user');
        state = state.copyWith(
          isCompiling: false,
          isCancelled: false,
          progress: 0.0,
          currentStep: null,
          errorMessage: 'Compilation cancelled',
        );
        return false;
      }

      state = state.copyWith(
        currentStep: 'Creating pack file...',
        progress: 0.80,
      );

      // Create pack file
      await Directory(gameDataPath).create(recursive: true);
      final packPath = path.join(gameDataPath, state.fullPackName);

      logger.info('Creating pack file: ${state.fullPackName}');
      logger.info('Output path: $packPath');

      // Progress range for pack creation: 0.80 to 0.95
      const packProgressStart = 0.80;
      const packProgressEnd = 0.95;
      const packProgressRange = packProgressEnd - packProgressStart;

      final packResult = await rpfmService.createPack(
        inputDirectory: tempDir.path,
        outputPackPath: packPath,
        languageCode: language.code,
        onProgress: (currentFile, totalFiles, fileName) {
          if (totalFiles > 0) {
            final fileProgress = currentFile / totalFiles;
            final overallProgress =
                packProgressStart + (packProgressRange * fileProgress);
            state = state.copyWith(
              currentStep: fileName.isNotEmpty
                  ? 'Adding: $fileName ($currentFile/$totalFiles)'
                  : 'Creating pack file...',
              progress: overallProgress,
            );
          }
        },
      );

      if (packResult.isErr) {
        throw Exception('Failed to create pack file: ${packResult.error}');
      }

      logger.info('Pack file created successfully');

      // Generate pack image with language flag if enabled
      if (state.generatePackImage) {
        state = state.copyWith(
          currentStep: 'Generating pack image...',
          progress: 0.96,
        );

        final imageGenerator = ServiceLocator.get<IPackImageGeneratorService>();
        await imageGenerator.ensurePackImage(
          packFileName: state.fullPackName,
          gameDataPath: gameDataPath,
          languageCode: language.code,
          generateImage: true,
          useAppIcon: true, // Use TWMT icon for compilations
        );
      }

      // Update compilation with output path
      await compilationRepo.updateAfterGeneration(
        state.compilationId!,
        packPath,
      );

      state = state.copyWith(
        isCompiling: false,
        progress: 1.0,
        currentStep: 'Completed!',
        successMessage: 'Pack generated: $packPath',
      );

      logger.info('Pack compilation completed', {
        'outputPath': packPath,
        'projectCount': projectIds.length,
        'totalFiles': totalFilesGenerated,
      });

      return true;
    } catch (e, stackTrace) {
      logger.error('Pack compilation failed', e, stackTrace);
      state = state.copyWith(
        isCompiling: false,
        progress: 0.0,
        currentStep: null,
        errorMessage: e.toString(),
      );
      return false;
    } finally {
      logger.info('Cleaning up temp directory...');
      await packUtils.cleanupTempDirectory(tempDir);
    }
  }
}
