import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/service_locator.dart';

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

/// Provider for dashboard statistics
@riverpod
Future<DashboardStats> dashboardStats(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final translationVersionRepo =
      ServiceLocator.get<TranslationVersionRepository>();

  // Get all projects
  final projectsResult = await projectRepo.getAll();
  final projects = projectsResult.isOk ? projectsResult.value : <Project>[];

  final totalProjects = projects.length;

  // Get global statistics from translation_versions table
  final statsResult =
      await translationVersionRepo.getGlobalStatistics();

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

/// Provider for recent projects (last 5)
@riverpod
Future<List<Project>> recentProjects(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final result = await projectRepo.getAll();

  if (result.isErr) {
    return [];
  }

  final projects = result.value;
  // Sort by updated_at descending and take first 5
  projects.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return projects.take(5).toList();
}
