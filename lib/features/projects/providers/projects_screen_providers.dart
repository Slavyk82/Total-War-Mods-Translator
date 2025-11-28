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
import '../../../repositories/project_repository.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../repositories/language_repository.dart';
import '../../../repositories/game_installation_repository.dart';
import '../../../repositories/workshop_mod_repository.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';
import '../../../services/mods/mod_update_analysis_service.dart';

/// View modes for displaying projects
enum ProjectViewMode { grid, list }

/// Sort options for projects
enum ProjectSortOption {
  name,
  dateModified,
  progress;

  String get displayName {
    switch (this) {
      case ProjectSortOption.name:
        return 'Name';
      case ProjectSortOption.dateModified:
        return 'Date Modified';
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

  const ProjectWithDetails({
    required this.project,
    this.gameInstallation,
    required this.languages,
    this.updateAnalysis,
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

  /// Check if there are changes to apply (same logic as Mods screen)
  bool get hasUpdates {
    return updateAnalysis?.hasChanges ?? false;
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
}

/// Project language with language info and translation stats
class ProjectLanguageWithInfo {
  final ProjectLanguage projectLanguage;
  final Language? language;
  final int totalUnits;
  final int translatedUnits;
  final int validatedUnits;

  const ProjectLanguageWithInfo({
    required this.projectLanguage,
    this.language,
    this.totalUnits = 0,
    this.translatedUnits = 0,
    this.validatedUnits = 0,
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

/// Provider for project repository
final projectRepositoryProvider = Provider<ProjectRepository>((ref) {
  return ProjectRepository();
});

/// Provider for project language repository
final projectLanguageRepositoryProvider = Provider<ProjectLanguageRepository>((ref) {
  return ProjectLanguageRepository();
});

/// Provider for language repository
final languageRepositoryProvider = Provider<LanguageRepository>((ref) {
  return LanguageRepository();
});

/// Provider for game installation repository
final gameInstallationRepositoryProvider = Provider<GameInstallationRepository>((ref) {
  return GameInstallationRepository();
});

/// Provider for workshop mod repository
final workshopModRepositoryProvider = Provider<WorkshopModRepository>((ref) {
  return WorkshopModRepository();
});

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
}

/// Provider for projects filter state
final projectsFilterProvider =
    NotifierProvider<ProjectsFilterNotifier, ProjectsFilterState>(
        ProjectsFilterNotifier.new);

/// Provider for all projects with details
final projectsWithDetailsProvider = FutureProvider<List<ProjectWithDetails>>((ref) async {
  final logging = ServiceLocator.get<LoggingService>();
  logging.debug('Starting projectsWithDetailsProvider');
  final projectRepo = ref.watch(projectRepositoryProvider);
  final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
  final langRepo = ref.watch(languageRepositoryProvider);
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final workshopModRepo = ref.watch(workshopModRepositoryProvider);
  final unitRepo = TranslationUnitRepository();
  final versionRepo = TranslationVersionRepository();
  final updateAnalysisService = ServiceLocator.get<ModUpdateAnalysisService>();

  // Fetch all projects
  final projectsResult = await projectRepo.getAll();
  if (projectsResult.isErr) {
    final error = projectsResult.unwrapErr();
    logging.error('Failed to fetch projects', error);
    throw Exception('Failed to load projects');
  }

  final projects = projectsResult.unwrap();
  logging.debug('Loaded projects', {'count': projects.length});
  final List<ProjectWithDetails> projectsWithDetails = [];

  // Load details for each project
  for (var project in projects) {
    // Get game installation
    GameInstallation? gameInstallation;
    final gameResult = await gameRepo.getById(project.gameInstallationId);
    if (gameResult.isOk) {
      gameInstallation = gameResult.unwrap();
    }

    // Auto-fill missing image URL from workshop folder if available
    if (project.imageUrl == null && project.sourceFilePath != null) {
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

    // Get total units count for this project
    final unitsResult = await unitRepo.getByProject(project.id);
    final totalUnits = unitsResult.isOk
        ? unitsResult.unwrap().where((u) => !u.isObsolete).length
        : 0;

    // Get project languages
    final langResult = await projectLangRepo.getByProject(project.id);
    final List<ProjectLanguageWithInfo> languagesWithInfo = [];

    if (langResult.isOk) {
      final projectLanguages = langResult.unwrap();

      // Load language info and stats for each project language
      for (final projLang in projectLanguages) {
        Language? language;
        final langInfoResult = await langRepo.getById(projLang.languageId);
        if (langInfoResult.isOk) {
          language = langInfoResult.unwrap();
        }

        // Get per-language translation stats
        final statsResult = await versionRepo.getLanguageStatistics(projLang.id);
        final stats = statsResult.isOk
            ? statsResult.unwrap()
            : ProjectStatistics.empty();

        languagesWithInfo.add(ProjectLanguageWithInfo(
          projectLanguage: projLang,
          language: language,
          totalUnits: totalUnits,
          translatedUnits: stats.translatedCount,
          validatedUnits: stats.validatedCount,
        ));
      }
    }

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
    }

    return true;
  }).toList();

  // Sort
  filtered.sort((a, b) {
    final comparison = switch (filter.sortBy) {
      ProjectSortOption.name => a.project.name.compareTo(b.project.name),
      ProjectSortOption.dateModified =>
        a.project.updatedAt.compareTo(b.project.updatedAt),
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


/// Provider for all game installations (for filter dropdown)
final allGameInstallationsProvider = FutureProvider<List<GameInstallation>>((ref) async {
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final result = await gameRepo.getAll();

  if (result.isErr) {
    throw Exception('Failed to load game installations');
  }

  return result.unwrap();
});

/// Provider for all languages (for filter dropdown)
final allLanguagesProvider = FutureProvider<List<Language>>((ref) async {
  try {
    final langRepo = ref.watch(languageRepositoryProvider);
    final result = await langRepo.getAll();

    if (result.isErr) {
      final error = result.unwrapErr();
      throw Exception('Failed to load languages: ${error.message}');
    }

    final languages = result.unwrap();
    if (languages.isEmpty) {
      // Return empty list instead of throwing - this is a valid state
      return languages;
    }

    return languages;
  } catch (e) {
    // Re-throw with more context
    throw Exception('Error loading languages: $e');
  }
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
