import 'package:json_annotation/json_annotation.dart';

part 'compilation_conflict.g.dart';

/// Type of compilation conflict between projects
enum CompilationConflictType {
  /// Same key exists in multiple projects with different source text
  @JsonValue('key_collision_different_source')
  keyCollisionDifferentSource,

  /// Same key exists in multiple projects with same source but different translations
  @JsonValue('translation_conflict')
  translationConflict,

  /// Same key, same source, same translation (duplicate - can auto-resolve)
  @JsonValue('duplicate')
  duplicate,
}

/// Resolution decision for a compilation conflict
enum CompilationConflictResolution {
  /// Use the first project's translation
  @JsonValue('use_first')
  useFirst,

  /// Use the second project's translation
  @JsonValue('use_second')
  useSecond,

  /// Skip this key entirely (exclude from compilation)
  @JsonValue('skip')
  skip,
}

/// Represents a conflict between translation units from different projects
@JsonSerializable()
class CompilationConflict {
  /// Unique identifier for this conflict
  final String id;

  /// The conflicting translation unit key
  final String key;

  /// Type of conflict
  @JsonKey(name: 'conflict_type')
  final CompilationConflictType conflictType;

  /// First project's data
  @JsonKey(name: 'first_entry')
  final ConflictEntry firstEntry;

  /// Second project's data
  @JsonKey(name: 'second_entry')
  final ConflictEntry secondEntry;

  /// Resolution decision (null if not yet resolved)
  final CompilationConflictResolution? resolution;

  /// ID of the project chosen for resolution
  @JsonKey(name: 'resolved_with_project_id')
  final String? resolvedWithProjectId;

  const CompilationConflict({
    required this.id,
    required this.key,
    required this.conflictType,
    required this.firstEntry,
    required this.secondEntry,
    this.resolution,
    this.resolvedWithProjectId,
  });

  /// Whether this conflict has been resolved
  bool get isResolved => resolution != null;

  /// Whether this conflict can be automatically resolved (duplicates)
  bool get canAutoResolve => conflictType == CompilationConflictType.duplicate;

  CompilationConflict copyWith({
    String? id,
    String? key,
    CompilationConflictType? conflictType,
    ConflictEntry? firstEntry,
    ConflictEntry? secondEntry,
    CompilationConflictResolution? resolution,
    String? resolvedWithProjectId,
  }) {
    return CompilationConflict(
      id: id ?? this.id,
      key: key ?? this.key,
      conflictType: conflictType ?? this.conflictType,
      firstEntry: firstEntry ?? this.firstEntry,
      secondEntry: secondEntry ?? this.secondEntry,
      resolution: resolution ?? this.resolution,
      resolvedWithProjectId: resolvedWithProjectId ?? this.resolvedWithProjectId,
    );
  }

  factory CompilationConflict.fromJson(Map<String, dynamic> json) =>
      _$CompilationConflictFromJson(json);

  Map<String, dynamic> toJson() => _$CompilationConflictToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CompilationConflict &&
        other.id == id &&
        other.key == key &&
        other.conflictType == conflictType;
  }

  @override
  int get hashCode => Object.hash(id, key, conflictType);
}

/// Data for one side of a conflict (one project's translation unit)
@JsonSerializable()
class ConflictEntry {
  /// Project ID
  @JsonKey(name: 'project_id')
  final String projectId;

  /// Project display name
  @JsonKey(name: 'project_name')
  final String projectName;

  /// Translation unit ID
  @JsonKey(name: 'unit_id')
  final String unitId;

  /// Source text
  @JsonKey(name: 'source_text')
  final String sourceText;

  /// Translated text (for the compilation's target language)
  @JsonKey(name: 'translated_text')
  final String? translatedText;

  /// Translation status
  final String? status;

  /// Whether manually edited
  @JsonKey(name: 'is_manually_edited')
  final bool isManuallyEdited;

  /// Last updated timestamp
  @JsonKey(name: 'updated_at')
  final int? updatedAt;

  /// Source .loc file path
  @JsonKey(name: 'source_loc_file')
  final String? sourceLocFile;

  const ConflictEntry({
    required this.projectId,
    required this.projectName,
    required this.unitId,
    required this.sourceText,
    this.translatedText,
    this.status,
    this.isManuallyEdited = false,
    this.updatedAt,
    this.sourceLocFile,
  });

  /// Whether this entry has a translation
  bool get hasTranslation =>
      translatedText != null && translatedText!.isNotEmpty;

  ConflictEntry copyWith({
    String? projectId,
    String? projectName,
    String? unitId,
    String? sourceText,
    String? translatedText,
    String? status,
    bool? isManuallyEdited,
    int? updatedAt,
    String? sourceLocFile,
  }) {
    return ConflictEntry(
      projectId: projectId ?? this.projectId,
      projectName: projectName ?? this.projectName,
      unitId: unitId ?? this.unitId,
      sourceText: sourceText ?? this.sourceText,
      translatedText: translatedText ?? this.translatedText,
      status: status ?? this.status,
      isManuallyEdited: isManuallyEdited ?? this.isManuallyEdited,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceLocFile: sourceLocFile ?? this.sourceLocFile,
    );
  }

  factory ConflictEntry.fromJson(Map<String, dynamic> json) =>
      _$ConflictEntryFromJson(json);

  Map<String, dynamic> toJson() => _$ConflictEntryToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConflictEntry &&
        other.projectId == projectId &&
        other.unitId == unitId;
  }

  @override
  int get hashCode => Object.hash(projectId, unitId);
}

/// Collection of conflict resolutions for a compilation
@JsonSerializable()
class CompilationConflictResolutions {
  /// Individual conflict resolutions (conflictId -> resolution)
  final Map<String, CompilationConflictResolution> resolutions;

  /// Project IDs associated with each resolution (conflictId -> projectId)
  @JsonKey(name: 'resolution_project_ids')
  final Map<String, String> resolutionProjectIds;

  /// Default resolution for unresolved conflicts
  @JsonKey(name: 'default_resolution')
  final CompilationConflictResolution? defaultResolution;

  /// Default project ID to use with default resolution
  @JsonKey(name: 'default_project_id')
  final String? defaultProjectId;

  const CompilationConflictResolutions({
    this.resolutions = const {},
    this.resolutionProjectIds = const {},
    this.defaultResolution,
    this.defaultProjectId,
  });

  /// Get resolution for a specific conflict
  CompilationConflictResolution? getResolution(String conflictId) {
    return resolutions[conflictId] ?? defaultResolution;
  }

  /// Get project ID for a specific conflict resolution
  String? getResolutionProjectId(String conflictId) {
    return resolutionProjectIds[conflictId] ?? defaultProjectId;
  }

  /// Check if a conflict is resolved
  bool isResolved(String conflictId) {
    return resolutions.containsKey(conflictId) || defaultResolution != null;
  }

  /// Add or update resolution for a conflict
  CompilationConflictResolutions setResolution(
    String conflictId,
    CompilationConflictResolution resolution,
    String? projectId,
  ) {
    final updatedResolutions =
        Map<String, CompilationConflictResolution>.from(resolutions);
    updatedResolutions[conflictId] = resolution;

    final updatedProjectIds = Map<String, String>.from(resolutionProjectIds);
    if (projectId != null) {
      updatedProjectIds[conflictId] = projectId;
    }

    return CompilationConflictResolutions(
      resolutions: updatedResolutions,
      resolutionProjectIds: updatedProjectIds,
      defaultResolution: defaultResolution,
      defaultProjectId: defaultProjectId,
    );
  }

  /// Set default resolution for all unresolved conflicts
  CompilationConflictResolutions setDefaultResolution(
    CompilationConflictResolution resolution,
    String? projectId,
  ) {
    return CompilationConflictResolutions(
      resolutions: resolutions,
      resolutionProjectIds: resolutionProjectIds,
      defaultResolution: resolution,
      defaultProjectId: projectId,
    );
  }

  CompilationConflictResolutions copyWith({
    Map<String, CompilationConflictResolution>? resolutions,
    Map<String, String>? resolutionProjectIds,
    CompilationConflictResolution? defaultResolution,
    String? defaultProjectId,
  }) {
    return CompilationConflictResolutions(
      resolutions: resolutions ?? this.resolutions,
      resolutionProjectIds: resolutionProjectIds ?? this.resolutionProjectIds,
      defaultResolution: defaultResolution ?? this.defaultResolution,
      defaultProjectId: defaultProjectId ?? this.defaultProjectId,
    );
  }

  factory CompilationConflictResolutions.fromJson(Map<String, dynamic> json) =>
      _$CompilationConflictResolutionsFromJson(json);

  Map<String, dynamic> toJson() => _$CompilationConflictResolutionsToJson(this);
}
