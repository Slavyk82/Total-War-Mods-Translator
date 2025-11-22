import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/language.dart';
import '../../../models/domain/game_installation.dart';
import '../../../repositories/project_repository.dart';
import '../../../repositories/project_language_repository.dart';
import '../../../repositories/language_repository.dart';
import '../../../repositories/game_installation_repository.dart';
import '../../../repositories/workshop_mod_repository.dart';
import '../../../services/service_locator.dart';
import '../../../services/shared/logging_service.dart';

/// View modes for displaying projects
enum ProjectViewMode { grid, list }

/// Sort options for projects
enum ProjectSortOption {
  name,
  dateModified,
  progress,
  status;

  String get displayName {
    switch (this) {
      case ProjectSortOption.name:
        return 'Name';
      case ProjectSortOption.dateModified:
        return 'Date Modified';
      case ProjectSortOption.progress:
        return 'Progress';
      case ProjectSortOption.status:
        return 'Status';
    }
  }
}

/// Filter state for projects screen
class ProjectsFilterState {
  final String searchQuery;
  final Set<ProjectStatus> statusFilters;
  final Set<String> gameFilters;
  final Set<String> languageFilters;
  final bool showOnlyWithUpdates;
  final ProjectSortOption sortBy;
  final bool sortAscending;
  final ProjectViewMode viewMode;
  final int currentPage;
  final int itemsPerPage;

  const ProjectsFilterState({
    this.searchQuery = '',
    this.statusFilters = const {},
    this.gameFilters = const {},
    this.languageFilters = const {},
    this.showOnlyWithUpdates = false,
    this.sortBy = ProjectSortOption.dateModified,
    this.sortAscending = false,
    this.viewMode = ProjectViewMode.grid,
    this.currentPage = 0,
    this.itemsPerPage = 20,
  });

  ProjectsFilterState copyWith({
    String? searchQuery,
    Set<ProjectStatus>? statusFilters,
    Set<String>? gameFilters,
    Set<String>? languageFilters,
    bool? showOnlyWithUpdates,
    ProjectSortOption? sortBy,
    bool? sortAscending,
    ProjectViewMode? viewMode,
    int? currentPage,
    int? itemsPerPage,
  }) {
    return ProjectsFilterState(
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilters: statusFilters ?? this.statusFilters,
      gameFilters: gameFilters ?? this.gameFilters,
      languageFilters: languageFilters ?? this.languageFilters,
      showOnlyWithUpdates: showOnlyWithUpdates ?? this.showOnlyWithUpdates,
      sortBy: sortBy ?? this.sortBy,
      sortAscending: sortAscending ?? this.sortAscending,
      viewMode: viewMode ?? this.viewMode,
      currentPage: currentPage ?? this.currentPage,
      itemsPerPage: itemsPerPage ?? this.itemsPerPage,
    );
  }
}

/// Extended project data with related information
class ProjectWithDetails {
  final Project project;
  final GameInstallation? gameInstallation;
  final List<ProjectLanguageWithInfo> languages;

  const ProjectWithDetails({
    required this.project,
    this.gameInstallation,
    required this.languages,
  });

  /// Calculate overall progress across all languages
  double get overallProgress {
    if (languages.isEmpty) return 0.0;
    final sum = languages.fold<double>(
      0.0,
      (sum, lang) => sum + lang.projectLanguage.progressPercent,
    );
    return sum / languages.length;
  }

  /// Check if any language has updates available
  bool get hasUpdates {
    return project.needsUpdateCheck || project.sourceModUpdated != null;
  }
}

/// Project language with language info
class ProjectLanguageWithInfo {
  final ProjectLanguage projectLanguage;
  final Language? language;

  const ProjectLanguageWithInfo({
    required this.projectLanguage,
    this.language,
  });
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
    state = state.copyWith(searchQuery: query, currentPage: 0);
  }

  void updateFilters({
    Set<ProjectStatus>? statusFilters,
    Set<String>? gameFilters,
    Set<String>? languageFilters,
    bool? showOnlyWithUpdates,
  }) {
    state = state.copyWith(
      statusFilters: statusFilters,
      gameFilters: gameFilters,
      languageFilters: languageFilters,
      showOnlyWithUpdates: showOnlyWithUpdates,
      currentPage: 0,
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

  void updatePage(int page) {
    state = state.copyWith(currentPage: page);
  }

  void clearFilters() {
    state = state.copyWith(
      statusFilters: const {},
      gameFilters: const {},
      languageFilters: const {},
      showOnlyWithUpdates: false,
      currentPage: 0,
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
  for (final project in projects) {
    // Get game installation
    GameInstallation? gameInstallation;
    final gameResult = await gameRepo.getById(project.gameInstallationId);
    if (gameResult.isOk) {
      gameInstallation = gameResult.unwrap();
    }

    // Get project languages
    final langResult = await projectLangRepo.getByProject(project.id);
    final List<ProjectLanguageWithInfo> languagesWithInfo = [];

    if (langResult.isOk) {
      final projectLanguages = langResult.unwrap();

      // Load language info for each project language
      for (final projLang in projectLanguages) {
        Language? language;
        final langInfoResult = await langRepo.getById(projLang.languageId);
        if (langInfoResult.isOk) {
          language = langInfoResult.unwrap();
        }

        languagesWithInfo.add(ProjectLanguageWithInfo(
          projectLanguage: projLang,
          language: language,
        ));
      }
    }

    projectsWithDetails.add(ProjectWithDetails(
      project: project,
      gameInstallation: gameInstallation,
      languages: languagesWithInfo,
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

    // Status filter
    if (filter.statusFilters.isNotEmpty) {
      if (!filter.statusFilters.contains(project.status)) return false;
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

    // Updates filter
    if (filter.showOnlyWithUpdates && !projectWithDetails.hasUpdates) {
      return false;
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
      ProjectSortOption.status =>
        a.project.status.index.compareTo(b.project.status.index),
    };
    return filter.sortAscending ? comparison : -comparison;
  });

  return filtered;
});

/// Provider for paginated projects
final paginatedProjectsProvider = FutureProvider<List<ProjectWithDetails>>((ref) async {
  final filtered = await ref.watch(filteredProjectsProvider.future);
  final filter = ref.watch(projectsFilterProvider);

  final startIndex = filter.currentPage * filter.itemsPerPage;
  final endIndex = (startIndex + filter.itemsPerPage).clamp(0, filtered.length);

  if (startIndex >= filtered.length) {
    return [];
  }

  return filtered.sublist(startIndex, endIndex);
});

/// Provider for total pages count
final totalPagesProvider = FutureProvider<int>((ref) async {
  final filtered = await ref.watch(filteredProjectsProvider.future);
  final filter = ref.watch(projectsFilterProvider);

  if (filtered.isEmpty) return 0;
  return (filtered.length / filter.itemsPerPage).ceil();
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
