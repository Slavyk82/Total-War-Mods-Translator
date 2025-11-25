import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';

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
  /// Local file last modified timestamp (Unix epoch seconds)
  final int? localFileLastModified;
  /// Analysis of changes for imported projects (null if not analyzed or not imported)
  final ModUpdateAnalysis? updateAnalysis;

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
    this.localFileLastModified,
    this.updateAnalysis,
  });

  /// Returns true if Steam version is newer than local file
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
    int? localFileLastModified,
    ModUpdateAnalysis? updateAnalysis,
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
      localFileLastModified: localFileLastModified ?? this.localFileLastModified,
      updateAnalysis: updateAnalysis ?? this.updateAnalysis,
    );
  }
}

