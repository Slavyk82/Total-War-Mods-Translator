import 'package:twmt/models/domain/project_metadata.dart';

/// Represents a mod detected in the Workshop folder but not yet imported as a project
class DetectedMod {
  final String workshopId;
  final String name;
  final String packFilePath;
  final String? imageUrl;
  final ProjectMetadata? metadata;
  final bool isAlreadyImported;
  final String? existingProjectId;

  const DetectedMod({
    required this.workshopId,
    required this.name,
    required this.packFilePath,
    this.imageUrl,
    this.metadata,
    this.isAlreadyImported = false,
    this.existingProjectId,
  });

  DetectedMod copyWith({
    String? workshopId,
    String? name,
    String? packFilePath,
    String? imageUrl,
    ProjectMetadata? metadata,
    bool? isAlreadyImported,
    String? existingProjectId,
  }) {
    return DetectedMod(
      workshopId: workshopId ?? this.workshopId,
      name: name ?? this.name,
      packFilePath: packFilePath ?? this.packFilePath,
      imageUrl: imageUrl ?? this.imageUrl,
      metadata: metadata ?? this.metadata,
      isAlreadyImported: isAlreadyImported ?? this.isAlreadyImported,
      existingProjectId: existingProjectId ?? this.existingProjectId,
    );
  }
}

