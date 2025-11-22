import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../repositories/project_repository.dart';
import '../../../repositories/translation_unit_repository.dart';
import '../../../repositories/translation_version_repository.dart';
import '../../../services/service_locator.dart';

part 'statistics_providers.g.dart';

/// Statistics overview data model
class StatisticsOverview {
  final int totalProjects;
  final int totalTranslations;
  final double tmReuseRate;
  final double averageQuality;

  const StatisticsOverview({
    required this.totalProjects,
    required this.totalTranslations,
    required this.tmReuseRate,
    required this.averageQuality,
  });
}

/// Daily progress data point
class DailyProgress {
  final DateTime date;
  final int translationsCount;

  const DailyProgress({
    required this.date,
    required this.translationsCount,
  });
}

/// Monthly translation activity data point
class MonthlyUsage {
  final DateTime month;
  final int translationsCount;

  const MonthlyUsage({
    required this.month,
    required this.translationsCount,
  });
}

/// TM effectiveness breakdown
class TmEffectiveness {
  final int exactMatches;
  final int fuzzyHigh;
  final int fuzzyMedium;
  final int llmTranslations;
  final int manualEdits;

  const TmEffectiveness({
    required this.exactMatches,
    required this.fuzzyHigh,
    required this.fuzzyMedium,
    required this.llmTranslations,
    required this.manualEdits,
  });

  int get total =>
      exactMatches + fuzzyHigh + fuzzyMedium + llmTranslations + manualEdits;
}

/// Project statistics
class ProjectStats {
  final String projectId;
  final String projectName;
  final int totalUnits;
  final int translatedUnits;
  final double progressPercentage;
  final double tmReuseRate;
  final String provider;

  const ProjectStats({
    required this.projectId,
    required this.projectName,
    required this.totalUnits,
    required this.translatedUnits,
    required this.progressPercentage,
    required this.tmReuseRate,
    required this.provider,
  });
}

/// Provider for statistics overview
@riverpod
Future<StatisticsOverview> statisticsOverview(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final unitRepo = ServiceLocator.get<TranslationUnitRepository>();
  final versionRepo = ServiceLocator.get<TranslationVersionRepository>();

  // Get all projects
  final projectsResult = await projectRepo.getAll();
  final projects = projectsResult.getOrElse([]);

  // Get all translation units (we only need the count)
  final unitsResult = await unitRepo.getAll();
  unitsResult.getOrElse([]);

  // Get all translation versions
  final versionsResult = await versionRepo.getAll();
  final versions = versionsResult.getOrElse([]);

  // Calculate total translations (completed versions)
  final completedVersions =
      versions.where((v) => v.isComplete && v.translatedText != null).toList();
  final totalTranslations = completedVersions.length;

  // Calculate TM reuse rate
  final manuallyEdited =
      completedVersions.where((v) => v.isManuallyEdited).length;
  final tmReused = totalTranslations - manuallyEdited;
  final tmReuseRate =
      totalTranslations > 0 ? (tmReused / totalTranslations) * 100 : 0.0;

  // Calculate average quality (confidence score)
  final versionsWithConfidence =
      completedVersions.where((v) => v.confidenceScore != null).toList();
  final averageQuality = versionsWithConfidence.isNotEmpty
      ? versionsWithConfidence
              .map((v) => v.confidenceScore!)
              .reduce((a, b) => a + b) /
          versionsWithConfidence.length *
          100
      : 0.0;

  return StatisticsOverview(
    totalProjects: projects.length,
    totalTranslations: totalTranslations,
    tmReuseRate: tmReuseRate,
    averageQuality: averageQuality,
  );
}

/// Provider for daily progress data
@riverpod
Future<List<DailyProgress>> dailyProgressData(Ref ref, int days) async {
  final versionRepo = ServiceLocator.get<TranslationVersionRepository>();

  // Get all translation versions
  final versionsResult = await versionRepo.getAll();
  final versions = versionsResult.getOrElse([]);

  // Calculate cutoff date
  final cutoffDate =
      DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch ~/
          1000;

  // Filter versions created within the time range
  final recentVersions = versions
      .where((v) =>
          v.createdAt >= cutoffDate &&
          v.isComplete &&
          v.translatedText != null)
      .toList();

  // Group by date
  final Map<DateTime, int> dailyCounts = {};

  for (var version in recentVersions) {
    final date = DateTime.fromMillisecondsSinceEpoch(version.createdAt * 1000);
    final dateKey = DateTime(date.year, date.month, date.day);

    dailyCounts[dateKey] = (dailyCounts[dateKey] ?? 0) + 1;
  }

  // Fill in missing days with zero counts
  final List<DailyProgress> result = [];
  final now = DateTime.now();
  final startDate = DateTime(now.year, now.month, now.day)
      .subtract(Duration(days: days - 1));

  for (int i = 0; i < days; i++) {
    final date = startDate.add(Duration(days: i));
    final count = dailyCounts[date] ?? 0;
    result.add(DailyProgress(date: date, translationsCount: count));
  }

  return result;
}

/// Provider for monthly usage data
@riverpod
Future<List<MonthlyUsage>> monthlyUsageData(Ref ref, int months) async {
  final versionRepo = ServiceLocator.get<TranslationVersionRepository>();

  // Get all translation versions
  final versionsResult = await versionRepo.getAll();
  final versions = versionsResult.getOrElse([]);

  // Calculate cutoff date
  final now = DateTime.now();
  final cutoffDate = DateTime(now.year, now.month - months, 1)
          .millisecondsSinceEpoch ~/
      1000;

  // Filter versions created within the time range
  final recentVersions = versions
      .where((v) =>
          v.createdAt >= cutoffDate &&
          v.isComplete &&
          v.translatedText != null)
      .toList();

  // Group by month
  final Map<DateTime, int> monthlyCounts = {};

  for (var version in recentVersions) {
    final date = DateTime.fromMillisecondsSinceEpoch(version.createdAt * 1000);
    final monthKey = DateTime(date.year, date.month, 1);

    monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
  }

  // Fill in missing months with zero counts
  final List<MonthlyUsage> result = [];
  final startMonth = DateTime(now.year, now.month - months + 1, 1);

  for (int i = 0; i < months; i++) {
    final month =
        DateTime(startMonth.year, startMonth.month + i, startMonth.day);
    final count = monthlyCounts[month] ?? 0;

    result.add(MonthlyUsage(month: month, translationsCount: count));
  }

  return result;
}

/// Provider for TM effectiveness data
@riverpod
Future<TmEffectiveness> tmEffectivenessData(Ref ref) async {
  final versionRepo = ServiceLocator.get<TranslationVersionRepository>();

  // Get all translation versions
  final versionsResult = await versionRepo.getAll();
  final versions = versionsResult.getOrElse([]);

  // Filter completed versions
  final completedVersions =
      versions.where((v) => v.isComplete && v.translatedText != null).toList();

  // Categorize by confidence score (as proxy for match quality)
  int exactMatches = 0;
  int fuzzyHigh = 0;
  int fuzzyMedium = 0;
  int llmTranslations = 0;
  int manualEdits = 0;

  for (var version in completedVersions) {
    if (version.isManuallyEdited) {
      manualEdits++;
    } else if (version.confidenceScore == null) {
      llmTranslations++;
    } else if (version.confidenceScore! >= 0.98) {
      exactMatches++;
    } else if (version.confidenceScore! >= 0.95) {
      fuzzyHigh++;
    } else if (version.confidenceScore! >= 0.85) {
      fuzzyMedium++;
    } else {
      llmTranslations++;
    }
  }

  return TmEffectiveness(
    exactMatches: exactMatches,
    fuzzyHigh: fuzzyHigh,
    fuzzyMedium: fuzzyMedium,
    llmTranslations: llmTranslations,
    manualEdits: manualEdits,
  );
}

/// Provider for project statistics data
@riverpod
Future<List<ProjectStats>> projectStatsData(Ref ref) async {
  final projectRepo = ServiceLocator.get<ProjectRepository>();
  final unitRepo = ServiceLocator.get<TranslationUnitRepository>();
  final versionRepo = ServiceLocator.get<TranslationVersionRepository>();

  // Get all projects
  final projectsResult = await projectRepo.getAll();
  final projects = projectsResult.getOrElse([]);

  final List<ProjectStats> result = [];

  for (var project in projects) {
    // Get units for this project
    final unitsResult = await unitRepo.getByProject(project.id);
    final units = unitsResult.getOrElse([]);

    if (units.isEmpty) {
      // Skip projects with no units
      continue;
    }

    // Get all versions for these units
    int translatedCount = 0;
    int manualEdits = 0;

    for (var unit in units) {
      final versionsResult = await versionRepo.getByUnit(unit.id);
      final versions = versionsResult.getOrElse([]);

      // Count completed versions
      final completed = versions
          .where((v) => v.isComplete && v.translatedText != null)
          .toList();
      if (completed.isNotEmpty) {
        translatedCount++;

        // Count manual edits
        if (completed.any((v) => v.isManuallyEdited)) {
          manualEdits++;
        }
      }
    }

    // Calculate metrics
    final totalUnits = units.length;
    final progressPercentage =
        totalUnits > 0 ? (translatedCount / totalUnits) * 100 : 0.0;
    final tmReused = translatedCount - manualEdits;
    final tmReuseRate =
        translatedCount > 0 ? (tmReused / translatedCount) * 100 : 0.0;

    result.add(ProjectStats(
      projectId: project.id,
      projectName: project.name,
      totalUnits: totalUnits,
      translatedUnits: translatedCount,
      progressPercentage: progressPercentage,
      tmReuseRate: tmReuseRate,
      provider: 'OpenAI',
    ));
  }

  return result;
}
