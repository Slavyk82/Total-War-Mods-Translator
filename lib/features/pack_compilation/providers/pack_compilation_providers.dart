import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../../../models/domain/compilation.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/game_installation.dart';
import '../../../models/domain/project_statistics.dart';
import '../../../providers/selected_game_provider.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../repositories/compilation_repository.dart';
import '../../../repositories/game_installation_repository.dart';
import '../../../repositories/language_repository.dart';
import '../../../repositories/project_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/file/i_loc_file_service.dart';
import '../../../services/file/pack_export_utils.dart';
import '../../../services/rpfm/i_rpfm_service.dart';
import '../../../services/shared/logging_service.dart';
import '../../projects/providers/projects_screen_providers.dart'
    show translationStatsVersionProvider;

// Re-export shared repository providers for backward compatibility
export '../../../providers/shared/repository_providers.dart'
    show
        compilationRepositoryProvider,
        projectRepositoryProvider,
        gameInstallationRepositoryProvider,
        languageRepositoryProvider,
        projectLanguageRepositoryProvider,
        translationVersionRepositoryProvider,
        activeLanguagesProvider,
        allLanguagesProvider,
        allGameInstallationsProvider;

part 'pack_compilation_providers.g.dart';

/// Project with translation statistics for a specific language
class ProjectWithTranslationInfo {
  final Project project;
  final int totalUnits;
  final int translatedUnits;

  const ProjectWithTranslationInfo({
    required this.project,
    this.totalUnits = 0,
    this.translatedUnits = 0,
  });

  String get id => project.id;
  String get displayName => project.displayName;
  String? get imageUrl => project.imageUrl;

  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }
}

/// Provider for getting the game installation from the selected game in sidebar
final currentGameInstallationProvider =
    FutureProvider<GameInstallation?>((ref) async {
  final selectedGame = await ref.watch(selectedGameProvider.future);
  if (selectedGame == null) return null;

  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final result = await gameRepo.getByGameCode(selectedGame.code);

  if (result.isErr) return null;
  return result.unwrap();
});


/// Compilation with related data
class CompilationWithDetails {
  final Compilation compilation;
  final GameInstallation? gameInstallation;
  final List<Project> projects;
  final int projectCount;

  const CompilationWithDetails({
    required this.compilation,
    this.gameInstallation,
    required this.projects,
    required this.projectCount,
  });
}

/// Provider for filtering projects by name in the compilation editor
@riverpod
class ProjectFilter extends _$ProjectFilter {
  @override
  String build() => '';

  void setFilter(String value) {
    state = value;
  }

  void clear() {
    state = '';
  }
}

/// Provider for all compilations with details (filtered by selected game)
final compilationsWithDetailsProvider =
    FutureProvider<List<CompilationWithDetails>>((ref) async {
  final compilationRepo = ref.watch(compilationRepositoryProvider);
  final projectRepo = ref.watch(projectRepositoryProvider);
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);

  // Watch the selected game to filter compilations
  final currentGameInstallation =
      await ref.watch(currentGameInstallationProvider.future);
  if (currentGameInstallation == null) {
    return <CompilationWithDetails>[];
  }

  // Fetch compilations for the selected game only
  final compilationsResult =
      await compilationRepo.getByGameInstallation(currentGameInstallation.id);
  if (compilationsResult.isErr) {
    throw Exception('Failed to load compilations');
  }

  final compilations = compilationsResult.unwrap();
  final List<CompilationWithDetails> results = [];

  for (final compilation in compilations) {
    // Get game installation
    GameInstallation? gameInstallation;
    final gameResult = await gameRepo.getById(compilation.gameInstallationId);
    if (gameResult.isOk) {
      gameInstallation = gameResult.unwrap();
    }

    // Get project IDs and projects
    final projectIdsResult =
        await compilationRepo.getProjectIds(compilation.id);
    final projectIds =
        projectIdsResult.isOk ? projectIdsResult.unwrap() : <String>[];

    final List<Project> projects = [];
    for (final projectId in projectIds) {
      final projectResult = await projectRepo.getById(projectId);
      if (projectResult.isOk) {
        projects.add(projectResult.unwrap());
      }
    }

    results.add(CompilationWithDetails(
      compilation: compilation,
      gameInstallation: gameInstallation,
      projects: projects,
      projectCount: projects.length,
    ));
  }

  return results;
});

/// Provider for filtered projects based on search text in compilation editor
@riverpod
AsyncValue<List<ProjectWithTranslationInfo>> filteredProjects(
  Ref ref,
  ProjectFilterParams params,
) {
  final projectsAsync = ref.watch(projectsWithTranslationProvider(params));
  final filter = ref.watch(projectFilterProvider).toLowerCase().trim();

  return projectsAsync.whenData((projects) {
    if (filter.isEmpty) return projects;

    return projects.where((p) {
      final name = p.displayName.toLowerCase();
      return name.contains(filter);
    }).toList();
  });
}

/// State for editing/creating a compilation
class CompilationEditorState {
  final String? compilationId;
  final String name;
  final String prefix;
  final String packName;
  final String? selectedLanguageId;
  final Set<String> selectedProjectIds;
  final bool isCompiling;
  final bool isCancelled;
  final double progress;
  final String? currentStep;
  final String? errorMessage;
  final String? successMessage;

  const CompilationEditorState({
    this.compilationId,
    this.name = '',
    this.prefix = '',
    this.packName = 'my_pack',
    this.selectedLanguageId,
    this.selectedProjectIds = const {},
    this.isCompiling = false,
    this.isCancelled = false,
    this.progress = 0.0,
    this.currentStep,
    this.errorMessage,
    this.successMessage,
  });

  /// Generate default prefix based on language code
  static String defaultPrefixForLanguage(String languageCode) {
    return '!!!!!!!!!!_${languageCode}_compilation_twmt_';
  }

  CompilationEditorState copyWith({
    String? compilationId,
    String? name,
    String? prefix,
    String? packName,
    String? selectedLanguageId,
    Set<String>? selectedProjectIds,
    bool? isCompiling,
    bool? isCancelled,
    double? progress,
    String? currentStep,
    String? errorMessage,
    String? successMessage,
  }) {
    return CompilationEditorState(
      compilationId: compilationId ?? this.compilationId,
      name: name ?? this.name,
      prefix: prefix ?? this.prefix,
      packName: packName ?? this.packName,
      selectedLanguageId: selectedLanguageId ?? this.selectedLanguageId,
      selectedProjectIds: selectedProjectIds ?? this.selectedProjectIds,
      isCompiling: isCompiling ?? this.isCompiling,
      isCancelled: isCancelled ?? this.isCancelled,
      progress: progress ?? this.progress,
      currentStep: currentStep ?? this.currentStep,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }

  bool get isEditing => compilationId != null;

  /// Full pack filename with lowercase enforced
  String get fullPackName => '$prefix$packName.pack'.toLowerCase();

  bool get canSave =>
      name.isNotEmpty &&
      prefix.isNotEmpty &&
      packName.isNotEmpty &&
      selectedLanguageId != null &&
      selectedProjectIds.isNotEmpty &&
      !isCompiling;

  bool get canCompile => canSave && !isCompiling;
}

/// Notifier for compilation editor
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
      newPrefix = CompilationEditorState.defaultPrefixForLanguage(language.code);
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

  /// Request cancellation of the current compilation
  /// This immediately kills any running RPFM process
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
      logger.info('Target language: ${language.displayName} (${language.code})');

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
          logger.info('Generated ${tsvPaths.length} loc files for ${project.displayName}');
          totalFilesGenerated += tsvPaths.length;
          await packUtils.copyTsvFilesToPackStructure(tsvPaths, tempDir);
        } else {
          logger.warning('Failed to generate loc files for ${project.displayName}');
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
            final overallProgress = packProgressStart + (packProgressRange * fileProgress);
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

final compilationEditorProvider =
    NotifierProvider<CompilationEditorNotifier, CompilationEditorState>(
  CompilationEditorNotifier.new,
);

/// Provider that exposes whether pack compilation is in progress.
/// Used by MainLayoutRouter to block navigation during compilation.
final compilationInProgressProvider = Provider<bool>((ref) {
  final state = ref.watch(compilationEditorProvider);
  return state.isCompiling;
});

/// Parameters for filtering projects
class ProjectFilterParams {
  final String? gameInstallationId;
  final String? languageId;

  const ProjectFilterParams({
    this.gameInstallationId,
    this.languageId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProjectFilterParams &&
          runtimeType == other.runtimeType &&
          gameInstallationId == other.gameInstallationId &&
          languageId == other.languageId;

  @override
  int get hashCode => gameInstallationId.hashCode ^ languageId.hashCode;
}

/// Provider for projects filtered by game installation AND language
/// Only returns projects that have a translation in the selected language
/// Includes translation statistics for the selected language
final projectsWithTranslationProvider =
    FutureProvider.family<List<ProjectWithTranslationInfo>, ProjectFilterParams>(
  (ref, params) async {
    // Watch version to trigger refresh when translations change
    ref.watch(translationStatsVersionProvider);
    
    if (params.gameInstallationId == null || params.languageId == null) {
      return [];
    }

    final projectRepo = ref.watch(projectRepositoryProvider);
    final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
    final versionRepo = ref.watch(translationVersionRepositoryProvider);

    // Get all projects for the game
    final projectsResult =
        await projectRepo.getByGameInstallation(params.gameInstallationId!);

    if (projectsResult.isErr) {
      throw Exception('Failed to load projects');
    }

    final allProjects = projectsResult.unwrap();
    final projectsWithInfo = <ProjectWithTranslationInfo>[];

    // Filter to only those that have a translation in the selected language
    for (final project in allProjects) {
      final langResult = await projectLangRepo.getByProjectAndLanguage(
        project.id,
        params.languageId!,
      );

      if (langResult.isOk) {
        final projectLanguage = langResult.unwrap();

        // Get translation stats for this language
        // Use stats.totalCount for consistency (excludes bracket-only and obsolete units)
        final statsResult =
            await versionRepo.getLanguageStatistics(projectLanguage.id);
        final stats = statsResult.isOk
            ? statsResult.unwrap()
            : ProjectStatistics.empty();

        // Progress = translated + validated (all units with actual translations)
        final translatedUnits = stats.translatedCount + stats.validatedCount;

        projectsWithInfo.add(ProjectWithTranslationInfo(
          project: project,
          totalUnits: stats.totalCount,
          translatedUnits: translatedUnits,
        ));
      }
    }

    return projectsWithInfo;
  },
);

/// Delete a compilation
Future<bool> deleteCompilation(String compilationId) async {
  final compilationRepo = ServiceLocator.get<CompilationRepository>();
  final result = await compilationRepo.delete(compilationId);
  return result.isOk;
}

/// Provider that generates BBCode links for selected projects in the compilation editor.
/// Format: [url=https://steamcommunity.com/sharedfiles/filedetails/?id={steamId}]{modTitle}[/url]
final compilationBBCodeProvider = FutureProvider<String>((ref) async {
  final state = ref.watch(compilationEditorProvider);
  final selectedIds = state.selectedProjectIds;

  if (selectedIds.isEmpty) {
    return '';
  }

  final projectRepo = ref.watch(projectRepositoryProvider);
  final bbCodeLines = <String>[];

  for (final projectId in selectedIds) {
    final result = await projectRepo.getById(projectId);
    if (result.isOk) {
      final project = result.unwrap();
      if (project.modSteamId != null && project.modSteamId!.isNotEmpty) {
        final url =
            'https://steamcommunity.com/sharedfiles/filedetails/?id=${project.modSteamId}';
        final title = project.displayName;
        bbCodeLines.add('[url=$url]$title[/url]');
      }
    }
  }

  return bbCodeLines.join('\n');
});
