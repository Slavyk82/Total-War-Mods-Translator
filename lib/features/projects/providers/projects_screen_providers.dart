import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../../models/domain/project.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/project_metadata.dart';
import '../../../models/domain/language.dart';
import '../../../models/domain/game_installation.dart';
import '../../../models/domain/project_statistics.dart';
import '../../../models/domain/mod_update_analysis.dart';
import '../../../models/domain/export_history.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/selected_game_provider.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../repositories/export_history_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';
import '../../../services/mods/mod_update_analysis_service.dart';

// Re-export shared repository providers for backward compatibility
export '../../../providers/shared/repository_providers.dart'
    show
        projectRepositoryProvider,
        projectLanguageRepositoryProvider,
        languageRepositoryProvider,
        gameInstallationRepositoryProvider,
        workshopModRepositoryProvider,
        allLanguagesProvider,
        allGameInstallationsProvider;

// Export batch selection and export providers
export 'batch_project_selection_provider.dart';
export 'batch_pack_export_notifier.dart';

/// View modes for displaying projects
enum ProjectViewMode { grid, list }

/// Sort options for projects
enum ProjectSortOption {
  name,
  dateModified,
  dateExported,
  progress;

  String get displayName {
    switch (this) {
      case ProjectSortOption.name:
        return 'Name';
      case ProjectSortOption.dateModified:
        return 'Date Modified';
      case ProjectSortOption.dateExported:
        return 'Date Exported';
      case ProjectSortOption.progress:
        return 'Progress';
    }
  }
}

/// Quick filter types for projects
enum ProjectQuickFilter {
  /// No filter - show all projects
  none,
  /// Projects that need a translation update (mod source changed)
  needsUpdate,
  /// Projects not yet 100% translated in ALL configured languages
  incomplete,
  /// Projects 100% translated in at least one language
  hasCompleteLanguage,
  /// Projects that have been exported at least once
  exported,
  /// Projects that have never been exported
  notExported,
  /// Projects modified since their last export
  exportOutdated,
}

/// Filter state for projects screen
class ProjectsFilterState {
  final String searchQuery;
  final Set<String> gameFilters;
  final Set<String> languageFilters;
  final bool showOnlyWithUpdates;
  final ProjectSortOption sortBy;
  final bool sortAscending;
  final ProjectViewMode viewMode;
  final ProjectQuickFilter quickFilter;

  const ProjectsFilterState({
    this.searchQuery = '',
    this.gameFilters = const {},
    this.languageFilters = const {},
    this.showOnlyWithUpdates = false,
    this.sortBy = ProjectSortOption.dateModified,
    this.sortAscending = false,
    this.viewMode = ProjectViewMode.grid,
    this.quickFilter = ProjectQuickFilter.none,
  });

  ProjectsFilterState copyWith({
    String? searchQuery,
    Set<String>? gameFilters,
    Set<String>? languageFilters,
    bool? showOnlyWithUpdates,
    ProjectSortOption? sortBy,
    bool? sortAscending,
    ProjectViewMode? viewMode,
    ProjectQuickFilter? quickFilter,
  }) {
    return ProjectsFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      gameFilters: gameFilters ?? this.gameFilters,
      languageFilters: languageFilters ?? this.languageFilters,
      showOnlyWithUpdates: showOnlyWithUpdates ?? this.showOnlyWithUpdates,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
      viewMode: viewMode ?? this.viewMode,
      quickFilter: quickFilter ?? this.quickFilter,
    );
  }
}

/// Extended project data with related information
class ProjectWithDetails {
  final Project project;
  final GameInstallation? gameInstallation;
  final List<ProjectLanguageWithInfo> languages;
  final ModUpdateAnalysis? updateAnalysis;
  final ExportHistory? lastPackExport;

  const ProjectWithDetails({
    required this.project,
    this.gameInstallation,
    required this.languages,
    this.updateAnalysis,
    this.lastPackExport,
  });

  /// Calculate overall progress across all languages
  double get overallProgress {
    if (languages.isEmpty) return 0.0;
    final sum = languages.fold<double>(
      0.0,
      (sum, lang) => sum + lang.progressPercent,
    );
    return sum / languages.length;
  }

  /// Check if there are pending changes to apply (excludes auto-applied changes)
  /// OR if the project was impacted by a mod update (flag set during scan)
  bool get hasUpdates {
    // Check the persistent flag first (set when mod update is applied)
    if (project.hasModUpdateImpact) return true;
    // Also check for pending analysis changes (for backwards compatibility)
    return updateAnalysis?.hasPendingChanges ?? false;
  }

  /// Check if all configured languages are 100% translated
  bool get isFullyTranslated {
    if (languages.isEmpty) return false;
    return languages.every((lang) => lang.isComplete);
  }

  /// Check if at least one language is 100% translated
  bool get hasAtLeastOneCompleteLanguage {
    if (languages.isEmpty) return false;
    return languages.any((lang) => lang.isComplete);
  }

  /// Check if the project has been exported at least once
  bool get hasBeenExported => lastPackExport != null;

  /// Check if the project was modified after the last export.
  /// Uses a 60-second margin to avoid false positives when the export
  /// process itself causes a minor timestamp update on the project.
  bool get isModifiedSinceLastExport {
    if (lastPackExport == null) return false;
    return project.updatedAt > lastPackExport!.exportedAt + 60;
  }
}

/// Project language with language info and translation stats
class ProjectLanguageWithInfo {
  final ProjectLanguage projectLanguage;
  final Language? language;
  final int totalUnits;
  final int translatedUnits;
  final int needsReviewUnits;

  const ProjectLanguageWithInfo({
    required this.projectLanguage,
    this.language,
    this.totalUnits = 0,
    this.translatedUnits = 0,
    this.needsReviewUnits = 0,
  });

  /// Calculate progress percentage based on actual translation counts
  /// Only units with status = 'translated' count as complete
  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }

  /// Check if this language is 100% translated
  bool get isComplete => totalUnits > 0 && translatedUnits >= totalUnits;
}

/// Notifier for translation statistics version counter.
/// Increment this to trigger refresh of all translation-related providers.
class TranslationStatsVersionNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state++;
}

/// Global version counter for translation statistics.
/// Used by pack compilation and other screens that display translation progress.
final translationStatsVersionProvider =
    NotifierProvider<TranslationStatsVersionNotifier, int>(
  TranslationStatsVersionNotifier.new,
);

/// State notifier for projects filter
class ProjectsFilterNotifier extends Notifier<ProjectsFilterState> {
  @override
  ProjectsFilterState build() => const ProjectsFilterState();

  void updateState(ProjectsFilterState newState) {
    state = newState;
  }

  void updateSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  void updateFilters({
    Set<String>? gameFilters,
    Set<String>? languageFilters,
    bool? showOnlyWithUpdates,
  }) {
    state = state.copyWith(
      gameFilters: gameFilters,
      languageFilters: languageFilters,
      showOnlyWithUpdates: showOnlyWithUpdates,
    );
  }

  void updateSort(ProjectSortOption sortBy, {bool? ascending}) {
    state = state.copyWith(
      sortBy: sortBy,
      sortAscending: ascending,
    );
  }

  void updateViewMode(ProjectViewMode viewMode) {
    state = state.copyWith(viewMode: viewMode);
  }

  void setQuickFilter(ProjectQuickFilter filter) {
    state = state.copyWith(quickFilter: filter);
  }

  void clearFilters() {
    state = state.copyWith(
      gameFilters: const {},
      languageFilters: const {},
      showOnlyWithUpdates: false,
      quickFilter: ProjectQuickFilter.none,
    );
  }

  /// Reset all filters including search query to default state.
  /// Called when navigating to the Projects screen.
  void resetAll() {
    state = const ProjectsFilterState();
  }
}

/// Provider for projects filter state
final projectsFilterProvider =
    NotifierProvider<ProjectsFilterNotifier, ProjectsFilterState>(
        ProjectsFilterNotifier.new);

/// Provider for all projects with details
final projectsWithDetailsProvider = FutureProvider<List<ProjectWithDetails>>((ref) async {
  // Watch translation stats version to refresh when stats change (e.g., mod update resets units)
  ref.watch(translationStatsVersionProvider);

  final logging = ServiceLocator.get<LoggingService>();
  logging.debug('Starting projectsWithDetailsProvider');
  final projectRepo = ref.watch(projectRepositoryProvider);
  final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
  final langRepo = ref.watch(languageRepositoryProvider);
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final workshopModRepo = ref.watch(workshopModRepositoryProvider);
  final versionRepo = ServiceLocator.get<TranslationVersionRepository>();
  final updateAnalysisService = ServiceLocator.get<ModUpdateAnalysisService>();
  final exportHistoryRepo = ServiceLocator.get<ExportHistoryRepository>();

  // Watch the selected game to filter projects
  final selectedGame = await ref.watch(selectedGameProvider.future);
  if (selectedGame == null) {
    logging.debug('No game selected, returning empty project list');
    return <ProjectWithDetails>[];
  }

  // Get the GameInstallation for the selected game
  final gameInstallationResult = await gameRepo.getByGameCode(selectedGame.code);
  if (gameInstallationResult.isErr) {
    logging.debug('No game installation found for ${selectedGame.code}');
    return <ProjectWithDetails>[];
  }
  final gameInstallation = gameInstallationResult.unwrap();

  // Fetch mod translation projects for the selected game only (exclude game translations)
  final projectsResult = await projectRepo.getModTranslationsByInstallation(gameInstallation.id);
  if (projectsResult.isErr) {
    final error = projectsResult.unwrapErr();
    logging.error('Failed to fetch projects', error);
    throw Exception('Failed to load projects');
  }

  final projects = projectsResult.unwrap();
  logging.debug('Loaded projects', {'count': projects.length});
  final List<ProjectWithDetails> projectsWithDetails = [];

  // Optimization: Pre-load all languages once to avoid N+1 queries
  // Languages are a small fixed set, so loading all is efficient
  final allLanguagesResult = await langRepo.getAll();
  final languagesMap = <String, Language>{};
  if (allLanguagesResult.isOk) {
    for (final lang in allLanguagesResult.unwrap()) {
      languagesMap[lang.id] = lang;
    }
  }

  // Optimization: Pre-load all game installations to avoid N+1 queries
  final allGamesResult = await gameRepo.getAll();
  final gamesMap = <String, GameInstallation>{};
  if (allGamesResult.isOk) {
    for (final game in allGamesResult.unwrap()) {
      gamesMap[game.id] = game;
    }
  }

  // Load details for each project
  for (var project in projects) {
    // Get game installation from pre-loaded map (O(1) instead of database query)
    final gameInstallation = gamesMap[project.gameInstallationId];

    // Auto-fill missing image URL from workshop folder if available
    // Skip for game translation projects (they use the game icon instead)
    if (project.imageUrl == null && project.sourceFilePath != null && project.isModTranslation) {
      final imagePath = await _findModImage(project.sourceFilePath!);
      if (imagePath != null) {
        final currentMetadata = project.parsedMetadata;
        final updatedMetadata = (currentMetadata ?? const ProjectMetadata()).copyWith(
          modImageUrl: imagePath,
        );
        
        final updatedProject = project.copyWith(
          metadata: updatedMetadata.toJsonString(),
        );
        
        // Save the updated project
        await projectRepo.update(updatedProject);
        project = updatedProject;
      }
    }

    // Get project languages
    final langResult = await projectLangRepo.getByProject(project.id);
    final List<ProjectLanguageWithInfo> languagesWithInfo = [];

    if (langResult.isOk) {
      final projectLanguages = langResult.unwrap();

      // Load language info and stats for each project language
      for (final projLang in projectLanguages) {
        // Get language from pre-loaded map (O(1) instead of database query)
        final language = languagesMap[projLang.languageId];

        // Get per-language translation stats
        // Statistics include totalCount which excludes bracket-only units
        final statsResult = await versionRepo.getLanguageStatistics(projLang.id);
        final stats = statsResult.isOk
            ? statsResult.unwrap()
            : ProjectStatistics.empty();

        languagesWithInfo.add(ProjectLanguageWithInfo(
          projectLanguage: projLang,
          language: language,
          totalUnits: stats.totalCount,
          translatedUnits: stats.translatedCount,
          needsReviewUnits: stats.errorCount,
        ));
      }
    }

    // Get last pack export for this project
    final lastPackExport = await exportHistoryRepo.getLastPackExportByProject(project.id);

    // Check for updates by comparing Steam timestamp vs local file timestamp
    // Same logic as DetectedMod.needsUpdate in the Mods screen
    ModUpdateAnalysis? updateAnalysis;
    bool needsUpdate = false;

    if (project.hasSourceFile &&
        project.sourceFilePath != null &&
        project.modSteamId != null) {
      // Get Steam Workshop timestamp from cache
      int? steamTimestamp;
      final workshopModResult =
          await workshopModRepo.getByWorkshopId(project.modSteamId!);
      if (workshopModResult.isOk) {
        steamTimestamp = workshopModResult.unwrap().timeUpdated;
      }

      // Get local file timestamp
      int? localTimestamp;
      final sourceFile = File(project.sourceFilePath!);
      if (await sourceFile.exists()) {
        final stat = await sourceFile.stat();
        localTimestamp = stat.modified.millisecondsSinceEpoch ~/ 1000;
      }

      // Compare timestamps (same as DetectedMod.needsUpdate)
      if (steamTimestamp != null && localTimestamp != null) {
        needsUpdate = steamTimestamp > localTimestamp;
      }

      // Only run expensive analysis if update is needed
      if (needsUpdate) {
        final analysisResult = await updateAnalysisService.analyzeChanges(
          projectId: project.id,
          packFilePath: project.sourceFilePath!,
        );
        if (analysisResult.isOk) {
          updateAnalysis = analysisResult.unwrap();
        }
      } else if (steamTimestamp != null && localTimestamp != null) {
        // No update needed - project is up to date
        updateAnalysis = ModUpdateAnalysis.empty;
      }
    }

    projectsWithDetails.add(ProjectWithDetails(
      project: project,
      gameInstallation: gameInstallation,
      languages: languagesWithInfo,
      updateAnalysis: updateAnalysis,
      lastPackExport: lastPackExport,
    ));
  }

  return projectsWithDetails;
});

/// Provider for filtered and sorted projects
final filteredProjectsProvider = FutureProvider<List<ProjectWithDetails>>((ref) async {
  final allProjects = await ref.watch(projectsWithDetailsProvider.future);
  final filter = ref.watch(projectsFilterProvider);

  var filtered = allProjects.where((projectWithDetails) {
    final project = projectWithDetails.project;

    // Search query filter
    if (filter.searchQuery.isNotEmpty) {
      final query = filter.searchQuery.toLowerCase();
      final matchesName = project.name.toLowerCase().contains(query);
      final matchesModId =
          project.modSteamId?.toLowerCase().contains(query) ?? false;
      if (!matchesName && !matchesModId) return false;
    }

    // Game filter
    if (filter.gameFilters.isNotEmpty) {
      if (!filter.gameFilters.contains(project.gameInstallationId)) {
        return false;
      }
    }

    // Language filter
    if (filter.languageFilters.isNotEmpty) {
      final hasLanguage = projectWithDetails.languages.any(
        (lang) => filter.languageFilters.contains(lang.projectLanguage.languageId),
      );
      if (!hasLanguage) return false;
    }

    // Updates filter (legacy - kept for compatibility)
    if (filter.showOnlyWithUpdates && !projectWithDetails.hasUpdates) {
      return false;
    }

    // Quick filter
    switch (filter.quickFilter) {
      case ProjectQuickFilter.none:
        break;
      case ProjectQuickFilter.needsUpdate:
        if (!projectWithDetails.hasUpdates) return false;
      case ProjectQuickFilter.incomplete:
        // Show projects that are NOT 100% translated in ALL languages
        if (projectWithDetails.isFullyTranslated) return false;
      case ProjectQuickFilter.hasCompleteLanguage:
        // Show projects with at least one 100% translated language
        if (!projectWithDetails.hasAtLeastOneCompleteLanguage) return false;
      case ProjectQuickFilter.exported:
        // Show only projects that have been exported
        if (!projectWithDetails.hasBeenExported) return false;
      case ProjectQuickFilter.notExported:
        // Show only projects that have never been exported
        if (projectWithDetails.hasBeenExported) return false;
      case ProjectQuickFilter.exportOutdated:
        // Show only projects modified since their last export
        if (!projectWithDetails.isModifiedSinceLastExport) return false;
    }

    return true;
  }).toList();

  // Sort
  filtered.sort((a, b) {
    final comparison = switch (filter.sortBy) {
      ProjectSortOption.name => a.project.name.compareTo(b.project.name),
      ProjectSortOption.dateModified =>
        a.project.updatedAt.compareTo(b.project.updatedAt),
      ProjectSortOption.dateExported => () {
        // Projects without export go to the end
        final aExport = a.lastPackExport?.exportedAt ?? 0;
        final bExport = b.lastPackExport?.exportedAt ?? 0;
        return aExport.compareTo(bExport);
      }(),
      ProjectSortOption.progress =>
        a.overallProgress.compareTo(b.overallProgress),
    };
    return filter.sortAscending ? comparison : -comparison;
  });

  return filtered;
});

/// Provider for all projects (no pagination)
final paginatedProjectsProvider = FutureProvider<List<ProjectWithDetails>>((ref) async {
  return ref.watch(filteredProjectsProvider.future);
});

/// Find mod preview image in the mod directory.
///
/// Searches for images in a specific priority order:
/// 1. Image with same name as pack file (e.g., my_mod.jpg for my_mod.pack)
/// 2. preview.* files
/// 3. Any image file in the directory
Future<String?> _findModImage(String packFilePath) async {
  const imageExtensions = ['.jpg', '.jpeg', '.png'];
  
  try {
    final packFile = File(packFilePath);
    if (!await packFile.exists()) return null;
    
    final modDir = packFile.parent;
    final packFileName = path.basenameWithoutExtension(packFilePath);
    
    // 1. Check for image with same name as .pack file
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, '$packFileName$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }
    
    // 2. Try preview.*
    for (final ext in imageExtensions) {
      final imagePath = path.join(modDir.path, 'preview$ext');
      if (await File(imagePath).exists()) {
        return imagePath;
      }
    }
    
    // 3. Try to find any image file
    final entries = await modDir.list().toList();
    for (final entity in entries) {
      if (entity is File) {
        final lowerPath = entity.path.toLowerCase();
        if (imageExtensions.any((ext) => lowerPath.endsWith(ext))) {
          return entity.path;
        }
      }
    }
  } catch (e) {
    // Ignore errors when searching for images
  }
  
  return null;
}

/// State for tracking resyncing projects
class ResyncingProjectsState {
  final Set<String> resyncingProjects;

  const ResyncingProjectsState({this.resyncingProjects = const {}});

  ResyncingProjectsState copyWith({Set<String>? resyncingProjects}) {
    return ResyncingProjectsState(
      resyncingProjects: resyncingProjects ?? this.resyncingProjects,
    );
  }
}

/// Notifier for managing project resync state and operations
class ProjectResyncNotifier extends Notifier<ResyncingProjectsState> {
  @override
  ResyncingProjectsState build() => const ResyncingProjectsState();

  /// Check if a project is currently being resynced
  bool isResyncing(String projectId) => state.resyncingProjects.contains(projectId);

  /// Resync a local pack project with its source file
  Future<void> resync(String projectId) async {
    final logging = LoggingService.instance;
    logging.info('Starting resync for project: $projectId');

    // Add to resyncing set
    state = state.copyWith(
      resyncingProjects: {...state.resyncingProjects, projectId},
    );

    try {
      // Get project details
      final projectRepo = ref.read(projectRepositoryProvider);
      final projectResult = await projectRepo.getById(projectId);

      if (projectResult.isErr) {
        throw Exception('Project not found: ${projectResult.error}');
      }

      final project = projectResult.unwrap();

      if (project.sourceFilePath == null) {
        throw Exception('Project has no source file path');
      }

      // Check if source file exists
      final sourceFile = File(project.sourceFilePath!);
      if (!await sourceFile.exists()) {
        throw Exception('Source file not found: ${project.sourceFilePath}');
      }

      // Use ModUpdateAnalysisService to analyze and apply changes
      final analysisService = ServiceLocator.get<ModUpdateAnalysisService>();

      // Analyze changes
      logging.info('Analyzing changes for project: $projectId');
      final analysisResult = await analysisService.analyzeChanges(
        projectId: projectId,
        packFilePath: project.sourceFilePath!,
      );

      if (analysisResult.isErr) {
        throw Exception('Failed to analyze changes: ${analysisResult.error}');
      }

      final analysis = analysisResult.unwrap();
      logging.info('Analysis complete: ${analysis.summary}');

      // Apply changes if any
      if (analysis.hasPendingChanges) {
        logging.info('Applying changes...');

        // Apply modified source texts
        if (analysis.hasModifiedUnits) {
          await analysisService.applyModifiedSourceTexts(
            projectId: projectId,
            analysis: analysis,
          );
          logging.info('Applied ${analysis.modifiedUnitsCount} modified source texts');
        }

        // Add new units
        if (analysis.hasNewUnits) {
          await analysisService.addNewUnits(
            projectId: projectId,
            analysis: analysis,
          );
          logging.info('Added ${analysis.newUnitsCount} new units');
        }

        // Mark removed units as obsolete
        if (analysis.hasRemovedUnits) {
          await analysisService.markRemovedUnitsObsolete(
            projectId: projectId,
            analysis: analysis,
          );
          logging.info('Marked ${analysis.removedUnitsCount} units as obsolete');
        }

        // Reactivate previously obsolete units that are back
        if (analysis.hasReactivatedUnits) {
          await analysisService.reactivateObsoleteUnits(
            projectId: projectId,
            analysis: analysis,
          );
          logging.info('Reactivated ${analysis.reactivatedUnitsCount} units');
        }

        // Update project timestamp
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await projectRepo.update(project.copyWith(updatedAt: now));

        logging.info('Resync complete for project: $projectId');
      } else {
        logging.info('No changes detected for project: $projectId');
      }

      // Invalidate projects provider to refresh the list
      ref.invalidate(projectsWithDetailsProvider);

    } catch (e, stack) {
      logging.error('Resync failed for project: $projectId', e, stack);
      rethrow;
    } finally {
      // Remove from resyncing set
      final newSet = Set<String>.from(state.resyncingProjects);
      newSet.remove(projectId);
      state = state.copyWith(resyncingProjects: newSet);
    }
  }
}

/// Provider for managing project resync state
final projectResyncProvider = NotifierProvider<ProjectResyncNotifier, ResyncingProjectsState>(
  ProjectResyncNotifier.new,
);
