import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/domain/project.dart';
import '../../../models/domain/project_language.dart';
import '../../../models/domain/language.dart';
import '../../../models/domain/game_installation.dart';
import '../../../models/domain/project_statistics.dart';
import '../../../providers/shared/repository_providers.dart';
import 'projects_screen_providers.dart';

// Re-export shared repository providers for backward compatibility
export '../../../providers/shared/repository_providers.dart'
    show translationUnitRepositoryProvider, translationVersionRepositoryProvider;

/// Extended project details with all related information
class ProjectDetails {
  final Project project;
  final GameInstallation? gameInstallation;
  final List<ProjectLanguageDetails> languages;
  final TranslationStats stats;

  const ProjectDetails({
    required this.project,
    this.gameInstallation,
    required this.languages,
    required this.stats,
  });
}

/// Project language with full language information and statistics
class ProjectLanguageDetails {
  final ProjectLanguage projectLanguage;
  final Language language;
  final int totalUnits;
  final int translatedUnits;
  final int pendingUnits;
  final int needsReviewUnits;

  const ProjectLanguageDetails({
    required this.projectLanguage,
    required this.language,
    this.totalUnits = 0,
    this.translatedUnits = 0,
    this.pendingUnits = 0,
    this.needsReviewUnits = 0,
  });

  /// Calculate progress percentage based on actual translation counts
  /// Only units with status = 'translated' count as complete
  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }
}

/// Translation statistics for a project
class TranslationStats {
  final int totalUnits;
  final int translatedUnits;
  final int pendingUnits;
  final int needsReviewUnits;
  final double tmReuseRate;
  final int tokensUsed;

  const TranslationStats({
    required this.totalUnits,
    this.translatedUnits = 0,
    this.pendingUnits = 0,
    this.needsReviewUnits = 0,
    this.tmReuseRate = 0.0,
    this.tokensUsed = 0,
  });

  /// Calculate overall progress percentage
  double get progressPercent {
    if (totalUnits == 0) return 0.0;
    return (translatedUnits / totalUnits) * 100;
  }
}

/// Provider for fetching project details by ID
final projectDetailsProvider = FutureProvider.family<ProjectDetails, String>((ref, projectId) async {
  // Watch translation stats version to refresh when stats change (e.g., mod update resets units)
  ref.watch(translationStatsVersionProvider);
  
  final projectRepo = ref.watch(projectRepositoryProvider);
  final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
  final langRepo = ref.watch(languageRepositoryProvider);
  final gameRepo = ref.watch(gameInstallationRepositoryProvider);
  final translationVersionRepo = ref.watch(translationVersionRepositoryProvider);

  // Fetch project
  final projectResult = await projectRepo.getById(projectId);
  if (projectResult.isErr) {
    throw Exception('Failed to load project: ${projectResult.unwrapErr()}');
  }
  final project = projectResult.unwrap();

  // Fetch game installation
  GameInstallation? gameInstallation;
  final gameResult = await gameRepo.getById(project.gameInstallationId);
  if (gameResult.isOk) {
    gameInstallation = gameResult.unwrap();
  }

  // Fetch project languages with language details and per-language statistics
  final List<ProjectLanguageDetails> languageDetails = [];
  final langResult = await projectLangRepo.getByProject(projectId);
  if (langResult.isOk) {
    final projectLanguages = langResult.unwrap();

    // Optimized: Batch fetch all languages in single query to avoid N+1 problem
    final languageIds = projectLanguages.map((pl) => pl.languageId).toList();
    final languagesResult = await langRepo.getByIds(languageIds);

    if (languagesResult.isOk) {
      // Create lookup map for O(1) access
      final languagesMap = <String, dynamic>{};
      for (final lang in languagesResult.unwrap()) {
        languagesMap[lang.id] = lang;
      }

      // Build details list with fast lookups and per-language stats
      for (final projLang in projectLanguages) {
        final language = languagesMap[projLang.languageId];
        if (language != null) {
          // Get statistics for this specific project language
          // Statistics include totalCount which excludes bracket-only units
          final langStatsResult = await translationVersionRepo.getLanguageStatistics(projLang.id);
          final langStats = langStatsResult.isOk 
              ? langStatsResult.unwrap() 
              : ProjectStatistics.empty();

          languageDetails.add(ProjectLanguageDetails(
            projectLanguage: projLang,
            language: language,
            totalUnits: langStats.totalCount,
            translatedUnits: langStats.translatedCount,
            pendingUnits: langStats.pendingCount,
            needsReviewUnits: langStats.errorCount,
          ));
        }
      }
    }
  }

  // Get total units from the first language stats (consistent with bracket-only exclusion)
  final totalUnits = languageDetails.isNotEmpty ? languageDetails.first.totalUnits : 0;

  // Fetch project-level translation statistics
  final statsResult = await translationVersionRepo.getProjectStatistics(projectId);
  final projectStats = statsResult.isOk
      ? statsResult.unwrap()
      : ProjectStatistics.empty();

  final translatedUnits = projectStats.translatedCount;
  final pendingUnits = projectStats.pendingCount;
  final needsReviewUnits = projectStats.errorCount; // errorCount = needs_review status

  // Calculate TM reuse rate based on translation_source field
  // Counts translations from TM (exact + fuzzy) vs total translated units
  final tmSourcedResult = await translationVersionRepo.countTmSourcedByProject(projectId);
  final tmSourcedUnits = tmSourcedResult.isOk ? tmSourcedResult.unwrap() : 0;
  final tmReuseRate = translatedUnits > 0
      ? tmSourcedUnits / translatedUnits
      : 0.0;

  final stats = TranslationStats(
    totalUnits: totalUnits,
    translatedUnits: translatedUnits,
    pendingUnits: pendingUnits,
    needsReviewUnits: needsReviewUnits,
    tmReuseRate: tmReuseRate,
    tokensUsed: translatedUnits * 150, // Estimate 150 tokens per translation
  );

  return ProjectDetails(
    project: project,
    gameInstallation: gameInstallation,
    languages: languageDetails,
    stats: stats,
  );
});

/// Provider for project languages by project ID
///
/// Uses batch fetching (getByIds) to avoid N+1 query pattern.
final projectLanguagesProvider = FutureProvider.family<List<ProjectLanguageDetails>, String>((ref, projectId) async {
  final projectLangRepo = ref.watch(projectLanguageRepositoryProvider);
  final langRepo = ref.watch(languageRepositoryProvider);

  final langResult = await projectLangRepo.getByProject(projectId);
  if (langResult.isErr) {
    throw Exception('Failed to load project languages');
  }

  final projectLanguages = langResult.unwrap();

  // Optimized: Batch fetch all languages in single query to avoid N+1 problem
  final languageIds = projectLanguages.map((pl) => pl.languageId).toList();
  final languagesResult = await langRepo.getByIds(languageIds);

  if (languagesResult.isErr) {
    throw Exception('Failed to load languages');
  }

  // Create lookup map for O(1) access
  final languagesMap = <String, Language>{};
  for (final lang in languagesResult.unwrap()) {
    languagesMap[lang.id] = lang;
  }

  // Build details list with fast lookups
  final List<ProjectLanguageDetails> languageDetails = [];
  for (final projLang in projectLanguages) {
    final language = languagesMap[projLang.languageId];
    if (language != null) {
      languageDetails.add(ProjectLanguageDetails(
        projectLanguage: projLang,
        language: language,
      ));
    }
  }

  return languageDetails;
});

/// Provider for translation statistics by project ID
final translationStatsProvider = FutureProvider.family<TranslationStats, String>((ref, projectId) async {
  final translationUnitRepo = ref.watch(translationUnitRepositoryProvider);
  final translationVersionRepo = ref.watch(translationVersionRepositoryProvider);

  final unitsResult = await translationUnitRepo.getByProject(projectId);
  final totalUnits = unitsResult.isOk ? unitsResult.unwrap().length : 0;

  // Get all stats in one optimized query
  final statsResult = await translationVersionRepo.getProjectStatistics(projectId);
  final projectStats = statsResult.isOk
      ? statsResult.unwrap()
      : ProjectStatistics.empty();

  final translatedUnits = projectStats.translatedCount;
  final pendingUnits = projectStats.pendingCount;
  final needsReviewUnits = projectStats.errorCount; // errorCount = needs_review status

  // Calculate TM reuse rate based on translation_source field
  // Counts translations from TM (exact + fuzzy) vs total translated units
  final tmSourcedResult = await translationVersionRepo.countTmSourcedByProject(projectId);
  final tmSourcedUnits = tmSourcedResult.isOk ? tmSourcedResult.unwrap() : 0;
  final tmReuseRate = translatedUnits > 0
      ? tmSourcedUnits / translatedUnits
      : 0.0;

  return TranslationStats(
    totalUnits: totalUnits,
    translatedUnits: translatedUnits,
    pendingUnits: pendingUnits,
    needsReviewUnits: needsReviewUnits,
    tmReuseRate: tmReuseRate,
    tokensUsed: translatedUnits * 150, // Estimate 150 tokens per translation
  );
});
