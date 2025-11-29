import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/mod_update_status.dart';

/// Represents a mod detected in the Workshop folder but not yet imported as a project
class DetectedMod {
  final String workshopId;
  final String name;
  final String packFilePath;
  final String? imageUrl;
  final ProjectMetadata? metadata;
  final bool isAlreadyImported;
  final String? existingProjectId;
  /// Whether the mod contains localization (.loc) files and is translatable
  final bool hasLocFiles;
  /// Last update timestamp from Steam Workshop API (Unix epoch seconds)
  final int? timeUpdated;
  /// Previously cached update timestamp from database (Unix epoch seconds)
  /// Used to detect if Steam has a new update since last scan
  final int? cachedTimeUpdated;
  /// Local file last modified timestamp (Unix epoch seconds)
  final int? localFileLastModified;
  /// Analysis of changes for imported projects (null if not analyzed or not imported)
  final ModUpdateAnalysis? updateAnalysis;
  
  /// Whether the mod is hidden from the main list by user preference
  final bool isHidden;

  const DetectedMod({
    required this.workshopId,
    required this.name,
    required this.packFilePath,
    this.imageUrl,
    this.metadata,
    this.isAlreadyImported = false,
    this.existingProjectId,
    this.hasLocFiles = true,
    this.timeUpdated,
    this.cachedTimeUpdated,
    this.localFileLastModified,
    this.updateAnalysis,
    this.isHidden = false,
  });

  /// Determines the update status based on Steam, cache, and local file timestamps.
  ///
  /// Logic:
  /// 1. If local file timestamp < Steam timestamp, user needs to download via launcher
  /// 2. If local file is current AND Steam has a new update (timestamp differs from cache)
  ///    AND there are translation changes, user should review
  /// 3. Otherwise, everything is up to date
  ///
  /// Important: We only show "hasChanges" when Steam actually has a NEW update.
  /// This prevents false positives when the user has intentionally modified
  /// source texts in their project (e.g., enriching names with titles).
  ModUpdateStatus get updateStatus {
    // Cannot determine if we don't have Steam timestamp
    if (timeUpdated == null) {
      return ModUpdateStatus.unknown;
    }

    // Cannot determine if we don't have local file timestamp
    if (localFileLastModified == null) {
      return ModUpdateStatus.unknown;
    }

    // Check if local file is outdated compared to Steam version
    // This happens when Steam has a newer version that hasn't been downloaded yet
    final localFileOutdated = timeUpdated! > localFileLastModified!;

    // If local file is outdated, user needs to download via game launcher
    if (localFileOutdated) {
      return ModUpdateStatus.needsDownload;
    }

    // Check if Steam has a NEW update since last scan
    // Only if cachedTimeUpdated exists and differs from current timeUpdated
    final hasNewSteamUpdate = cachedTimeUpdated != null &&
        timeUpdated != cachedTimeUpdated;

    // Local file is current - check for translation changes ONLY if:
    // 1. Project is already imported
    // 2. Steam has a NEW update (timestamp changed since last scan)
    // 3. Analysis shows actual changes
    if (isAlreadyImported &&
        hasNewSteamUpdate &&
        updateAnalysis != null &&
        updateAnalysis!.hasChanges) {
      return ModUpdateStatus.hasChanges;
    }

    return ModUpdateStatus.upToDate;
  }

  /// Returns true if local file is outdated and needs to be downloaded via game launcher.
  /// This is when Steam timestamp > local file timestamp.
  bool get needsDownload => updateStatus == ModUpdateStatus.needsDownload;

  /// Returns true if Steam version is newer than local file (legacy compatibility)
  @Deprecated('Use updateStatus or needsDownload instead')
  bool get needsUpdate {
    if (timeUpdated == null || localFileLastModified == null) {
      return false;
    }
    return timeUpdated! > localFileLastModified!;
  }

  /// Returns true if there are translation changes to review
  bool get hasTranslationChanges => updateAnalysis?.hasChanges ?? false;

  DetectedMod copyWith({
    String? workshopId,
    String? name,
    String? packFilePath,
    String? imageUrl,
    ProjectMetadata? metadata,
    bool? isAlreadyImported,
    String? existingProjectId,
    bool? hasLocFiles,
    int? timeUpdated,
    int? cachedTimeUpdated,
    int? localFileLastModified,
    ModUpdateAnalysis? updateAnalysis,
    bool? isHidden,
  }) {
    return DetectedMod(
      workshopId: workshopId ?? this.workshopId,
      name: name ?? this.name,
      packFilePath: packFilePath ?? this.packFilePath,
      imageUrl: imageUrl ?? this.imageUrl,
      metadata: metadata ?? this.metadata,
      isAlreadyImported: isAlreadyImported ?? this.isAlreadyImported,
      existingProjectId: existingProjectId ?? this.existingProjectId,
      hasLocFiles: hasLocFiles ?? this.hasLocFiles,
      timeUpdated: timeUpdated ?? this.timeUpdated,
      cachedTimeUpdated: cachedTimeUpdated ?? this.cachedTimeUpdated,
      localFileLastModified: localFileLastModified ?? this.localFileLastModified,
      updateAnalysis: updateAnalysis ?? this.updateAnalysis,
      isHidden: isHidden ?? this.isHidden,
    );
  }
}

