/// Statistics for a project's translation progress.
///
/// Aggregated counts from translation_versions table for a specific project.
class ProjectStatistics {
  /// Number of translated units (has translated_text)
  final int translatedCount;

  /// Number of pending units (status = 'pending')
  final int pendingCount;

  /// Number of validated units (status in 'approved', 'reviewed')
  final int validatedCount;

  /// Number of units with errors (status = 'error')
  final int errorCount;

  const ProjectStatistics({
    required this.translatedCount,
    required this.pendingCount,
    required this.validatedCount,
    required this.errorCount,
  });

  /// Empty statistics (all zeros)
  factory ProjectStatistics.empty() => const ProjectStatistics(
        translatedCount: 0,
        pendingCount: 0,
        validatedCount: 0,
        errorCount: 0,
      );
}
