/// Information about a mod update for UI display.
///
/// Represents the update status of a mod project, including
/// version details and affected translations count.
class ModUpdateInfo {
  /// Project ID
  final String projectId;

  /// Mod name from project
  final String modName;

  /// Current version ID in database
  final String currentVersionId;

  /// Current version string (e.g., '1.0.0')
  final String currentVersionString;

  /// Latest version ID (null if no update available)
  final String? latestVersionId;

  /// Latest version string (null if no update available)
  final String? latestVersionString;

  /// When the update became available
  final DateTime updateAvailableDate;

  /// Whether an update is available
  final bool hasUpdate;

  /// Number of translations affected by this update
  final int affectedTranslations;

  const ModUpdateInfo({
    required this.projectId,
    required this.modName,
    required this.currentVersionId,
    required this.currentVersionString,
    this.latestVersionId,
    this.latestVersionString,
    required this.updateAvailableDate,
    required this.hasUpdate,
    required this.affectedTranslations,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ModUpdateInfo &&
          runtimeType == other.runtimeType &&
          projectId == other.projectId &&
          modName == other.modName &&
          currentVersionId == other.currentVersionId &&
          currentVersionString == other.currentVersionString &&
          latestVersionId == other.latestVersionId &&
          latestVersionString == other.latestVersionString &&
          updateAvailableDate == other.updateAvailableDate &&
          hasUpdate == other.hasUpdate &&
          affectedTranslations == other.affectedTranslations;

  @override
  int get hashCode => Object.hash(
        projectId,
        modName,
        currentVersionId,
        currentVersionString,
        latestVersionId,
        latestVersionString,
        updateAvailableDate,
        hasUpdate,
        affectedTranslations,
      );

  @override
  String toString() => 'ModUpdateInfo(project: $modName, '
      'current: $currentVersionString, '
      'latest: ${latestVersionString ?? 'N/A'}, '
      'hasUpdate: $hasUpdate, affected: $affectedTranslations)';
}
