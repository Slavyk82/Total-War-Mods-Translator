import 'package:json_annotation/json_annotation.dart';

part 'import_conflict.g.dart';

/// Represents a conflict between imported and existing translation
@JsonSerializable()
class ImportConflict {
  /// Translation unit key
  final String key;

  /// Existing translation data
  @JsonKey(name: 'existing_data')
  final ConflictTranslation existingData;

  /// Imported translation data
  @JsonKey(name: 'imported_data')
  final ConflictTranslation importedData;

  /// Whether source texts differ
  @JsonKey(name: 'source_text_differs')
  final bool sourceTextDiffers;

  /// Resolution decision (null if not yet resolved)
  final ConflictResolution? resolution;

  const ImportConflict({
    required this.key,
    required this.existingData,
    required this.importedData,
    this.sourceTextDiffers = false,
    this.resolution,
  });

  /// Whether this conflict has been resolved
  bool get isResolved => resolution != null;

  ImportConflict copyWith({
    String? key,
    ConflictTranslation? existingData,
    ConflictTranslation? importedData,
    bool? sourceTextDiffers,
    ConflictResolution? resolution,
  }) {
    return ImportConflict(
      key: key ?? this.key,
      existingData: existingData ?? this.existingData,
      importedData: importedData ?? this.importedData,
      sourceTextDiffers: sourceTextDiffers ?? this.sourceTextDiffers,
      resolution: resolution ?? this.resolution,
    );
  }

  factory ImportConflict.fromJson(Map<String, dynamic> json) =>
      _$ImportConflictFromJson(json);

  Map<String, dynamic> toJson() => _$ImportConflictToJson(this);
}

/// Translation data for conflict comparison
@JsonSerializable()
class ConflictTranslation {
  /// Source text
  @JsonKey(name: 'source_text')
  final String? sourceText;

  /// Translated text
  @JsonKey(name: 'translated_text')
  final String? translatedText;

  /// Translation status
  final String? status;

  /// Last updated timestamp
  @JsonKey(name: 'updated_at')
  final int? updatedAt;

  /// Changed by (user/LLM)
  @JsonKey(name: 'changed_by')
  final String? changedBy;

  /// Notes
  final String? notes;

  const ConflictTranslation({
    this.sourceText,
    this.translatedText,
    this.status,
    this.updatedAt,
    this.changedBy,
    this.notes,
  });

  ConflictTranslation copyWith({
    String? sourceText,
    String? translatedText,
    String? status,
    int? updatedAt,
    String? changedBy,
    String? notes,
  }) {
    return ConflictTranslation(
      sourceText: sourceText ?? this.sourceText,
      translatedText: translatedText ?? this.translatedText,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      changedBy: changedBy ?? this.changedBy,
      notes: notes ?? this.notes,
    );
  }

  factory ConflictTranslation.fromJson(Map<String, dynamic> json) =>
      _$ConflictTranslationFromJson(json);

  Map<String, dynamic> toJson() => _$ConflictTranslationToJson(this);
}

/// Resolution decision for a conflict
enum ConflictResolution {
  @JsonValue('keep_existing')
  keepExisting,
  @JsonValue('use_imported')
  useImported,
  @JsonValue('merge')
  merge,
}

/// Collection of conflict resolutions
@JsonSerializable()
class ConflictResolutions {
  /// Individual conflict resolutions (key -> resolution)
  final Map<String, ConflictResolution> resolutions;

  /// Default resolution for unresolved conflicts
  @JsonKey(name: 'default_resolution')
  final ConflictResolution? defaultResolution;

  const ConflictResolutions({
    this.resolutions = const {},
    this.defaultResolution,
  });

  /// Get resolution for a specific key
  ConflictResolution? getResolution(String key) {
    return resolutions[key] ?? defaultResolution;
  }

  /// Add or update resolution for a key
  ConflictResolutions setResolution(String key, ConflictResolution resolution) {
    final updatedResolutions = Map<String, ConflictResolution>.from(resolutions);
    updatedResolutions[key] = resolution;
    return ConflictResolutions(
      resolutions: updatedResolutions,
      defaultResolution: defaultResolution,
    );
  }

  ConflictResolutions copyWith({
    Map<String, ConflictResolution>? resolutions,
    ConflictResolution? defaultResolution,
  }) {
    return ConflictResolutions(
      resolutions: resolutions ?? this.resolutions,
      defaultResolution: defaultResolution ?? this.defaultResolution,
    );
  }

  factory ConflictResolutions.fromJson(Map<String, dynamic> json) =>
      _$ConflictResolutionsFromJson(json);

  Map<String, dynamic> toJson() => _$ConflictResolutionsToJson(this);
}
