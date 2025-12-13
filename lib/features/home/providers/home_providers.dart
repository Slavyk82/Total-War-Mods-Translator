import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/repositories/game_installation_repository.dart';

part 'home_providers.g.dart';

/// Dashboard statistics model
class DashboardStats {
  final int totalProjects;
  final int totalTranslationUnits;
  final int translatedUnits;
  final int pendingUnits;
  final int totalTranslatedWords;

  const DashboardStats({
    required this.totalProjects,
    required this.totalTranslationUnits,
    required this.translatedUnits,
    required this.pendingUnits,
    required this.totalTranslatedWords,
  });

  double get translationProgress {
    if (totalTranslationUnits == 0) return 0.0;
    return (translatedUnits / totalTranslationUnits) * 100;
  }
}

/// Provider for dashboard statistics filtered by selected game
@riverpod
Future<DashboardStats> dashboardStats(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final translationVersionRepo =
      ServiceLocator.get<TranslationVersionRepository>();
  final gameInstallationRepo =
      ServiceLocator.get<GameInstallationRepository>();

  // Get selected game
  final selectedGame = await ref.watch(selectedGameProvider.future);
  final gameCode = selectedGame?.code;

  // Get projects filtered by game
  List<Project> projects = [];
  if (gameCode != null) {
    // Find game installation for the selected game code
    final gameInstallationResult =
        await gameInstallationRepo.getByGameCode(gameCode);
    if (gameInstallationResult.isOk) {
      final gameInstallation = gameInstallationResult.value;
      final projectsResult =
          await projectRepo.getByGameInstallation(gameInstallation.id);
      projects = projectsResult.isOk ? projectsResult.value : [];
    }
  } else {
    // No game selected, get all projects
    final projectsResult = await projectRepo.getAll();
    projects = projectsResult.isOk ? projectsResult.value : [];
  }

  final totalProjects = projects.length;

  // Get global statistics filtered by game code
  final statsResult =
      await translationVersionRepo.getGlobalStatistics(gameCode: gameCode);

  if (statsResult.isOk) {
    final stats = statsResult.value;
    return DashboardStats(
      totalProjects: totalProjects,
      totalTranslationUnits: stats.totalUnits,
      translatedUnits: stats.translatedUnits,
      pendingUnits: stats.pendingUnits,
      totalTranslatedWords: stats.totalTranslatedWords,
    );
  }

  // Fallback if query fails
  return DashboardStats(
    totalProjects: totalProjects,
    totalTranslationUnits: 0,
    translatedUnits: 0,
    pendingUnits: 0,
    totalTranslatedWords: 0,
  );
}

/// Provider for recent projects (last 5) filtered by selected game
@riverpod
Future<List<Project>> recentProjects(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final gameInstallationRepo =
      ServiceLocator.get<GameInstallationRepository>();

  // Get selected game
  final selectedGame = await ref.watch(selectedGameProvider.future);
  final gameCode = selectedGame?.code;

  List<Project> projects = [];
  if (gameCode != null) {
    // Find game installation for the selected game code
    final gameInstallationResult =
        await gameInstallationRepo.getByGameCode(gameCode);
    if (gameInstallationResult.isOk) {
      final gameInstallation = gameInstallationResult.value;
      final projectsResult =
          await projectRepo.getByGameInstallation(gameInstallation.id);
      projects = projectsResult.isOk ? projectsResult.value : [];
    }
  } else {
    // No game selected, get all projects
    final result = await projectRepo.getAll();
    projects = result.isOk ? result.value : [];
  }

  // Sort by updated_at descending and take first 5
  projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return projects.take(5).toList();
}
