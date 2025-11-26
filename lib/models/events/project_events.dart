import 'domain_event.dart';

/// Base class for all project-related events
abstract class ProjectEvent extends DomainEvent {
  final String projectId;

  ProjectEvent({required this.projectId}) : super.now();
}

/// Event emitted when a new project is created
class ProjectCreatedEvent extends ProjectEvent {
  final String projectName;
  final String gameInstallationId;
  final List<String> targetLanguageIds;

  ProjectCreatedEvent({
    required super.projectId,
    required this.projectName,
    required this.gameInstallationId,
    required this.targetLanguageIds,
  });
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'ProjectCreatedEvent(projectId: $projectId, name: $projectName, '
      'languages: ${targetLanguageIds.length})';
}

/// Event emitted when a project is updated (settings, name, etc.)
class ProjectUpdatedEvent extends ProjectEvent {
  final String? projectName;
  final String? description;
  final Map<String, dynamic> changes;

  ProjectUpdatedEvent({
    required super.projectId,
    this.projectName,
    this.description,
    required this.changes,
  });
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'ProjectUpdatedEvent(projectId: $projectId, changes: ${changes.keys.join(", ")})';
}

/// Event emitted when a project language progress updates
class ProjectLanguageProgressUpdatedEvent extends ProjectEvent {
  final String projectLanguageId;
  final String languageId;
  final double oldProgress;
  final double newProgress;

  ProjectLanguageProgressUpdatedEvent({
    required this.projectLanguageId,
    required super.projectId,
    required this.languageId,
    required this.oldProgress,
    required this.newProgress,
  });

  double get progressDelta => newProgress - oldProgress;
  bool get isComplete => newProgress >= 100.0;
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'ProjectLanguageProgressUpdatedEvent(projectLanguageId: $projectLanguageId, '
      '${oldProgress.toStringAsFixed(1)}% -> ${newProgress.toStringAsFixed(1)}%)';
}

/// Event emitted when a mod update is detected
class ModUpdateDetectedEvent extends ProjectEvent {
  final String versionString;
  final int unitsAdded;
  final int unitsModified;
  final int unitsDeleted;

  ModUpdateDetectedEvent({
    required super.projectId,
    required this.versionString,
    required this.unitsAdded,
    required this.unitsModified,
    required this.unitsDeleted,
  });

  int get totalChanges => unitsAdded + unitsModified + unitsDeleted;
  bool get hasSignificantChanges => totalChanges >= 10;
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'ModUpdateDetectedEvent(projectId: $projectId, version: $versionString, '
      'changes: +$unitsAdded ~$unitsModified -$unitsDeleted)';
}

/// Event emitted when a project is completed
class ProjectCompletedEvent extends ProjectEvent {
  final String projectName;
  final int totalUnits;
  final int completedLanguages;
  final Duration totalDuration;

  ProjectCompletedEvent({
    required super.projectId,
    required this.projectName,
    required this.totalUnits,
    required this.completedLanguages,
    required this.totalDuration,
  });
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'ProjectCompletedEvent(projectId: $projectId, name: $projectName, '
      'units: $totalUnits, languages: $completedLanguages, '
      'duration: ${totalDuration.inHours}h)';
}

/// Event emitted when project export is generated
class ProjectExportedEvent extends ProjectEvent {
  final String languageId;
  final String outputFilePath;
  final int exportedUnits;
  final String format;

  ProjectExportedEvent({
    required super.projectId,
    required this.languageId,
    required this.outputFilePath,
    required this.exportedUnits,
    required this.format,
  });
  @override
  Map<String, dynamic> toJson() {
    throw UnimplementedError('toJson() must be implemented');
  }

  @override
  String toString() =>
      'ProjectExportedEvent(projectId: $projectId, units: $exportedUnits, '
      'format: $format, path: $outputFilePath)';
}
