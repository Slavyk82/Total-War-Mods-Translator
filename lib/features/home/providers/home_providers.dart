import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/services/service_locator.dart';

part 'home_providers.g.dart';

/// Dashboard statistics model
class DashboardStats {
  final int totalProjects;
  final int totalTranslationUnits;
  final int translatedUnits;
  final int pendingUnits;

  const DashboardStats({
    required this.totalProjects,
    required this.totalTranslationUnits,
    required this.translatedUnits,
    required this.pendingUnits,
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
  final translationUnitRepo = ServiceLocator.get<TranslationUnitRepository>();

  // Get all projects
  final projectsResult = await projectRepo.getAll();
  final projects = projectsResult.isOk ? projectsResult.value : <Project>[];

  final totalProjects = projects.length;

  // Get translation unit stats (simplified - would need to join with versions for real counts)
  final unitsResult = await translationUnitRepo.getAll();
  final units = unitsResult.isOk ? unitsResult.value : [];

  final totalTranslationUnits = units.length;
  // This is simplified - in reality we'd need to check translation_versions table
  final translatedUnits = (totalTranslationUnits * 0.6).floor(); // Placeholder
  final pendingUnits = totalTranslationUnits - translatedUnits;

  return DashboardStats(
    totalProjects: totalProjects,
    totalTranslationUnits: totalTranslationUnits,
    translatedUnits: translatedUnits,
    pendingUnits: pendingUnits,
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
