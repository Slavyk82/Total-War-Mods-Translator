/// Global statistics for the dashboard.
///
/// Aggregated counts across all projects.
class GlobalStatistics {
  /// Total unique translation units
  final int totalUnits;

  /// Number of units with non-empty translation
  final int translatedUnits;

  /// Number of units pending translation
  final int pendingUnits;

  /// Total word count in translated texts
  final int totalTranslatedWords;

  const GlobalStatistics({
    required this.totalUnits,
    required this.translatedUnits,
    required this.pendingUnits,
    required this.totalTranslatedWords,
  });

  /// Empty statistics (all zeros)
  factory GlobalStatistics.empty() => const GlobalStatistics(
        totalUnits: 0,
        translatedUnits: 0,
        pendingUnits: 0,
        totalTranslatedWords: 0,
      );
}

/// Statistics for a project's translation progress.
///
/// Aggregated counts from translation_versions table for a specific project.
/// Excludes bracket-only units (e.g., "[hidden]") from all counts.
class ProjectStatistics {
  /// Total number of translatable units (excluding bracket-only)
  final int totalCount;

  /// Number of translated units (has translated_text)
  final int translatedCount;

  /// Number of pending units (status = 'pending')
  final int pendingCount;

  /// Number of validated units (status in 'approved', 'reviewed')
  final int validatedCount;

  /// Number of units with errors (status = 'error')
  final int errorCount;

  const ProjectStatistics({
    this.totalCount = 0,
    required this.translatedCount,
    required this.pendingCount,
    required this.validatedCount,
    required this.errorCount,
  });

  /// Empty statistics (all zeros)
  factory ProjectStatistics.empty() => const ProjectStatistics(
        totalCount: 0,
        translatedCount: 0,
        pendingCount: 0,
        validatedCount: 0,
        errorCount: 0,
      );
}
