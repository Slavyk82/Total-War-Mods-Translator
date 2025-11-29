/// Status of a mod's update state relative to Steam Workshop and local files.
///
/// This enum represents the different states a mod can be in when comparing:
/// 1. Steam Workshop update timestamp (remote)
/// 2. Cached update timestamp (last known)
/// 3. Local file modification timestamp
enum ModUpdateStatus {
  /// Everything is up to date:
  /// - Steam timestamp matches cached timestamp (no new update on Steam)
  /// - OR local file is current with Steam version
  /// - No translation changes detected
  upToDate,

  /// Steam has a newer version but local file is outdated:
  /// - Steam timestamp > cached timestamp (new update detected)
  /// - Local file timestamp < Steam timestamp
  /// - User needs to launch the game to download the update
  needsDownload,

  /// Local file is up to date but translation changes detected:
  /// - Local file timestamp >= Steam timestamp (file is current)
  /// - .loc file analysis shows changes compared to project
  /// - User should review and update translations
  hasChanges,

  /// Cannot determine status (missing timestamps or analysis failed)
  unknown,
}

/// Extension methods for ModUpdateStatus
extension ModUpdateStatusExtension on ModUpdateStatus {
  /// Whether this status indicates the user needs to take action
  bool get requiresAction =>
      this == ModUpdateStatus.needsDownload || this == ModUpdateStatus.hasChanges;

  /// Whether the local pack file needs to be downloaded
  bool get needsDownload => this == ModUpdateStatus.needsDownload;

  /// Whether there are translation changes to review
  bool get hasTranslationChanges => this == ModUpdateStatus.hasChanges;

  /// Whether the mod is fully up to date
  bool get isUpToDate => this == ModUpdateStatus.upToDate;

  /// Get a user-friendly label for this status
  String get label {
    switch (this) {
      case ModUpdateStatus.upToDate:
        return 'Up to date';
      case ModUpdateStatus.needsDownload:
        return 'Update available';
      case ModUpdateStatus.hasChanges:
        return 'Changes detected';
      case ModUpdateStatus.unknown:
        return 'Unknown';
    }
  }

  /// Get a tooltip message explaining this status
  String get tooltipMessage {
    switch (this) {
      case ModUpdateStatus.upToDate:
        return 'This mod is up to date with the Steam Workshop version.';
      case ModUpdateStatus.needsDownload:
        return 'A new version is available on Steam Workshop.\nLaunch the game to download the update.';
      case ModUpdateStatus.hasChanges:
        return 'The mod has been updated and contains translation changes.\nReview the changes to update your project.';
      case ModUpdateStatus.unknown:
        return 'Unable to determine the update status.';
    }
  }
}
