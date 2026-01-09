import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/domain/game_installation.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/project_statistics.dart';
import '../../../providers/selected_game_provider.dart';
import '../../../providers/shared/repository_providers.dart';
import '../../../repositories/compilation_repository.dart';
import '../../../services/service_locator.dart';
import '../../projects/providers/projects_screen_providers.dart'
    show translationStatsVersionProvider;
import '../models/compilation_editor_state.dart';
import '../models/compilation_with_details.dart';
import '../models/project_filter_params.dart';
import '../models/project_with_translation_info.dart';
import 'compilation_editor_notifier.dart';

// Re-export models for backward compatibility
export '../models/compilation_editor_state.dart';
export '../models/compilation_with_details.dart';
export '../models/project_filter_params.dart';
export '../models/project_with_translation_info.dart';
export 'compilation_editor_notifier.dart';

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

/// Provider for getting the game installation from the selected game in sidebar.
final currentGameInstallationProvider =
    FutureProvider<GameInstallation?>((ref) async {
  final selectedGame = await ref.watch(selectedGameProvider.future);
  if (selectedGame == null) return null;

  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final result = await gameRepo.getByGameCode(selectedGame.code);

  if (result.isErr) return null;
  return result.unwrap();
});

/// Provider for filtering projects by name in the compilation editor.
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

/// Provider for all compilations with details (filtered by selected game).
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

/// Provider for filtered projects based on search text in compilation editor.
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

/// Provider for the compilation editor notifier.
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

/// Provider for projects filtered by game installation AND language.
/// Only returns projects that have a translation in the selected language.
/// Includes translation statistics for the selected language.
final projectsWithTranslationProvider = FutureProvider.family<
    List<ProjectWithTranslationInfo>, ProjectFilterParams>(
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

/// Delete a compilation.
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
