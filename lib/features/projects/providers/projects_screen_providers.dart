import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/providers/projects_data_providers.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../providers/shared/logging_providers.dart';
import '../../../providers/shared/service_providers.dart';

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

// Re-export the shared project-data providers (extracted to lib/providers)
// so existing same-feature consumers keep resolving ProjectWithDetails,
// projectsWithDetailsProvider, translationStatsVersionProvider, etc.
export 'package:twmt/providers/projects_data_providers.dart';

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
  /// Projects with at least one unit flagged as `needs_review`
  needsReview,
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

/// Map a URL filter token (e.g. `needs-review`) to a [ProjectQuickFilter].
///
/// Used by the Home dashboard action cards that navigate to
/// `/work/projects?filter=<token>`. Returns null for unknown or missing tokens.
ProjectQuickFilter? projectQuickFilterFromUrlToken(String? token) {
  switch (token) {
    case 'needs-review':
      return ProjectQuickFilter.needsReview;
    case 'needs-update':
      return ProjectQuickFilter.needsUpdate;
    case 'incomplete':
      return ProjectQuickFilter.incomplete;
    case 'ready-to-compile':
      return ProjectQuickFilter.hasCompleteLanguage;
    case 'exported':
      return ProjectQuickFilter.exported;
    case 'not-exported':
      return ProjectQuickFilter.notExported;
    case 'export-outdated':
      return ProjectQuickFilter.exportOutdated;
    default:
      return null;
  }
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

  /// Click on a sortable column header: same field flips direction, a new
  /// field switches and picks a sensible default (ASC for name, DESC for
  /// dates and progress).
  void toggleSort(ProjectSortOption sortBy) {
    if (state.sortBy == sortBy) {
      state = state.copyWith(sortAscending: !state.sortAscending);
    } else {
      state = state.copyWith(
        sortBy: sortBy,
        sortAscending: sortBy == ProjectSortOption.name,
      );
    }
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
      case ProjectQuickFilter.needsReview:
        // Show projects that still have units flagged for review
        if (!projectWithDetails.hasNeedsReviewUnits) return false;
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

/// Counts of projects matching each [ProjectQuickFilter].
///
/// Computed against the full, unfiltered project list so each pill shows the
/// same total regardless of the currently selected filter — mirroring the
/// behavior of the Mods screen filter pills.
final projectQuickFilterCountsProvider =
    FutureProvider<Map<ProjectQuickFilter, int>>((ref) async {
  final all = await ref.watch(projectsWithDetailsProvider.future);
  var needsUpdate = 0;
  var needsReview = 0;
  var incomplete = 0;
  var hasComplete = 0;
  var exported = 0;
  var notExported = 0;
  var exportOutdated = 0;
  for (final p in all) {
    if (p.hasUpdates) needsUpdate++;
    if (p.hasNeedsReviewUnits) needsReview++;
    if (!p.isFullyTranslated) incomplete++;
    if (p.hasAtLeastOneCompleteLanguage) hasComplete++;
    if (p.hasBeenExported) {
      exported++;
    } else {
      notExported++;
    }
    if (p.isModifiedSinceLastExport) exportOutdated++;
  }
  return {
    ProjectQuickFilter.needsUpdate: needsUpdate,
    ProjectQuickFilter.needsReview: needsReview,
    ProjectQuickFilter.incomplete: incomplete,
    ProjectQuickFilter.hasCompleteLanguage: hasComplete,
    ProjectQuickFilter.exported: exported,
    ProjectQuickFilter.notExported: notExported,
    ProjectQuickFilter.exportOutdated: exportOutdated,
  };
});

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
    final logging = ref.read(loggingServiceProvider);
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
      final analysisService = ref.read(modUpdateAnalysisServiceProvider);

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
