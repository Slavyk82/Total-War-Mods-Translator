import 'package:json_annotation/json_annotation.dart';

part 'project_language.g.dart';

/// Project language status enumeration
enum ProjectLanguageStatus {
  @JsonValue('pending')
  pending,
  @JsonValue('translating')
  translating,
  @JsonValue('completed')
  completed,
  @JsonValue('error')
  error,
}

/// Represents a target language for a translation project.
///
/// Each project can have multiple target languages. This model tracks the
/// translation progress and status for a specific language within a project.
@JsonSerializable()
class ProjectLanguage {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the parent project
  @JsonKey(name: 'project_id')
  final String projectId;

  /// ID of the target language
  @JsonKey(name: 'language_id')
  final String languageId;

  /// Current status of translation for this language
  final ProjectLanguageStatus status;

  /// Translation progress percentage (0-100)
  @JsonKey(name: 'progress_percent')
  final double progressPercent;

  /// Unix timestamp when the project language was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the project language was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const ProjectLanguage({
    required this.id,
    required this.projectId,
    required this.languageId,
    this.status = ProjectLanguageStatus.pending,
    this.progressPercent = 0.0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Returns true if translation is pending
  bool get isPending => status == ProjectLanguageStatus.pending;

  /// Returns true if translation is in progress
  bool get isTranslating => status == ProjectLanguageStatus.translating;

  /// Returns true if translation is completed
  bool get isCompleted => status == ProjectLanguageStatus.completed;

  /// Returns true if there was an error
  bool get hasError => status == ProjectLanguageStatus.error;

  /// Returns true if translation is active (translating)
  bool get isActive => status == ProjectLanguageStatus.translating;

  /// Returns true if translation is finished (completed or error)
  bool get isFinished =>
      status == ProjectLanguageStatus.completed ||
      status == ProjectLanguageStatus.error;

  /// Returns the progress as an integer percentage (0-100)
  int get progressPercentInt => progressPercent.round();

  /// Returns true if the translation has started
  bool get hasStarted => progressPercent > 0;

  /// Returns true if the translation is partially complete
  bool get isPartiallyComplete =>
      progressPercent > 0 && progressPercent < 100;

  /// Returns true if the translation is fully complete (100%)
  bool get isFullyComplete => progressPercent >= 100;

  /// Returns a status display string
  String get statusDisplay {
    switch (status) {
      case ProjectLanguageStatus.pending:
        return 'Pending';
      case ProjectLanguageStatus.translating:
        return 'Translating';
      case ProjectLanguageStatus.completed:
        return 'Completed';
      case ProjectLanguageStatus.error:
        return 'Error';
    }
  }

  /// Returns a formatted progress string (e.g., "45%")
  String get progressDisplay => '$progressPercentInt%';

  ProjectLanguage copyWith({
    String? id,
    String? projectId,
    String? languageId,
    ProjectLanguageStatus? status,
    double? progressPercent,
    int? createdAt,
    int? updatedAt,
  }) {
    return ProjectLanguage(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      languageId: languageId ?? this.languageId,
      status: status ?? this.status,
      progressPercent: progressPercent ?? this.progressPercent,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory ProjectLanguage.fromJson(Map<String, dynamic> json) =>
      _$ProjectLanguageFromJson(json);

  Map<String, dynamic> toJson() => _$ProjectLanguageToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProjectLanguage &&
        other.id == id &&
        other.projectId == projectId &&
        other.languageId == languageId &&
        other.status == status &&
        other.progressPercent == progressPercent &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      projectId.hashCode ^
      languageId.hashCode ^
      status.hashCode ^
      progressPercent.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() => 'ProjectLanguage(id: $id, projectId: $projectId, languageId: $languageId, status: $status, progress: $progressPercentInt%)';
}
