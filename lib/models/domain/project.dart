import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/domain/project_metadata.dart';

part 'project.g.dart';

/// Represents a translation project in TWMT.
///
/// A project contains all information about translating a specific Total War mod
/// or the base game itself. It includes the source details, target languages,
/// translation settings, and current progress.
///
/// Projects have two types:
/// - 'mod': For translating Steam Workshop mods (default)
/// - 'game': For translating the base game using local_xx.pack files
@JsonSerializable()
class Project {
  /// Unique identifier (UUID)
  final String id;

  /// Project name
  final String name;

  /// Steam Workshop ID of the mod (if from Steam)
  @JsonKey(name: 'mod_steam_id')
  final String? modSteamId;

  /// Current version of the source mod
  @JsonKey(name: 'mod_version')
  final String? modVersion;

  /// ID of the associated game installation
  @JsonKey(name: 'game_installation_id')
  final String gameInstallationId;

  /// Path to source language file
  @JsonKey(name: 'source_file_path')
  final String? sourceFilePath;

  /// Path where translated files will be output
  @JsonKey(name: 'output_file_path')
  final String? outputFilePath;

  /// Unix timestamp of last update check for source mod
  @JsonKey(name: 'last_update_check')
  final int? lastUpdateCheck;

  /// Unix timestamp when source mod was last updated
  @JsonKey(name: 'source_mod_updated')
  final int? sourceModUpdated;

  /// Number of translation units per batch
  @JsonKey(name: 'batch_size')
  final int batchSize;

  /// Number of batches to process in parallel (1-5)
  @JsonKey(name: 'parallel_batches')
  final int parallelBatches;

  /// Custom translation prompt/instructions
  @JsonKey(name: 'custom_prompt')
  final String? customPrompt;

  /// Unix timestamp when the project was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when the project was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  /// Unix timestamp when the project was completed (if applicable)
  @JsonKey(name: 'completed_at')
  final int? completedAt;

  /// Additional metadata stored as JSON string
  final String? metadata;

  /// Flag indicating the project was impacted by a mod update.
  /// Set to true when mod update changes are applied (new units, modified texts, etc.)
  /// Users can clear this flag after reviewing the project.
  @JsonKey(
    name: 'has_mod_update_impact',
    fromJson: _boolFromInt,
    toJson: _boolToInt,
  )
  final bool hasModUpdateImpact;

  /// Type of project: 'mod' for mod translations, 'game' for base game translations.
  /// Defaults to 'mod' for backward compatibility.
  @JsonKey(name: 'project_type')
  final String projectType;

  /// Source language code for game translations (e.g., 'en', 'fr').
  /// Only used when projectType == 'game'.
  @JsonKey(name: 'source_language_code')
  final String? sourceLanguageCode;

  /// Steam Workshop ID of the published translation pack.
  /// Distinct from modSteamId (the source mod being translated).
  @JsonKey(name: 'published_steam_id')
  final String? publishedSteamId;

  const Project({
    required this.id,
    required this.name,
    this.modSteamId,
    this.modVersion,
    required this.gameInstallationId,
    this.sourceFilePath,
    this.outputFilePath,
    this.lastUpdateCheck,
    this.sourceModUpdated,
    this.batchSize = 25,
    this.parallelBatches = 3,
    this.customPrompt,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.metadata,
    this.hasModUpdateImpact = false,
    this.projectType = 'mod',
    this.sourceLanguageCode,
    this.publishedSteamId,
  });

  /// Returns true if the project has a source file configured
  bool get hasSourceFile =>
      sourceFilePath != null && sourceFilePath!.isNotEmpty;

  /// Returns true if the project has an output path configured
  bool get hasOutputPath =>
      outputFilePath != null && outputFilePath!.isNotEmpty;

  /// Returns true if the project is from Steam Workshop
  bool get isFromSteamWorkshop =>
      modSteamId != null && modSteamId!.isNotEmpty;

  /// Returns true if this is a game translation project
  bool get isGameTranslation => projectType == 'game';

  /// Returns true if this is a mod translation project
  bool get isModTranslation => projectType == 'mod';

  /// Returns true if the project needs an update check
  bool get needsUpdateCheck {
    if (lastUpdateCheck == null) return true;
    final daysSinceCheck = (DateTime.now().millisecondsSinceEpoch ~/ 1000 -
            lastUpdateCheck!) ~/
        86400;
    return daysSinceCheck >= 1; // Check daily
  }

  /// Parse and return project metadata
  ProjectMetadata? get parsedMetadata => ProjectMetadata.fromJsonString(metadata);

  /// Get mod title from metadata, fallback to name
  String get displayName => parsedMetadata?.modTitle ?? name;

  /// Get mod image URL from metadata
  String? get imageUrl => parsedMetadata?.modImageUrl;


  Project copyWith({
    String? id,
    String? name,
    String? modSteamId,
    String? modVersion,
    String? gameInstallationId,
    String? sourceFilePath,
    String? outputFilePath,
    int? lastUpdateCheck,
    int? sourceModUpdated,
    int? batchSize,
    int? parallelBatches,
    String? customPrompt,
    int? createdAt,
    int? updatedAt,
    int? completedAt,
    String? metadata,
    bool? hasModUpdateImpact,
    String? projectType,
    String? sourceLanguageCode,
    String? publishedSteamId,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      modSteamId: modSteamId ?? this.modSteamId,
      modVersion: modVersion ?? this.modVersion,
      gameInstallationId: gameInstallationId ?? this.gameInstallationId,
      sourceFilePath: sourceFilePath ?? this.sourceFilePath,
      outputFilePath: outputFilePath ?? this.outputFilePath,
      lastUpdateCheck: lastUpdateCheck ?? this.lastUpdateCheck,
      sourceModUpdated: sourceModUpdated ?? this.sourceModUpdated,
      batchSize: batchSize ?? this.batchSize,
      parallelBatches: parallelBatches ?? this.parallelBatches,
      customPrompt: customPrompt ?? this.customPrompt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      completedAt: completedAt ?? this.completedAt,
      metadata: metadata ?? this.metadata,
      hasModUpdateImpact: hasModUpdateImpact ?? this.hasModUpdateImpact,
      projectType: projectType ?? this.projectType,
      sourceLanguageCode: sourceLanguageCode ?? this.sourceLanguageCode,
      publishedSteamId: publishedSteamId ?? this.publishedSteamId,
    );
  }

  factory Project.fromJson(Map<String, dynamic> json) =>
      _$ProjectFromJson(json);

  Map<String, dynamic> toJson() => _$ProjectToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Project &&
        other.id == id &&
        other.name == name &&
        other.modSteamId == modSteamId &&
        other.modVersion == modVersion &&
        other.gameInstallationId == gameInstallationId &&
        other.sourceFilePath == sourceFilePath &&
        other.outputFilePath == outputFilePath &&
        other.lastUpdateCheck == lastUpdateCheck &&
        other.sourceModUpdated == sourceModUpdated &&
        other.batchSize == batchSize &&
        other.parallelBatches == parallelBatches &&
        other.customPrompt == customPrompt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.completedAt == completedAt &&
        other.metadata == metadata &&
        other.hasModUpdateImpact == hasModUpdateImpact &&
        other.projectType == projectType &&
        other.sourceLanguageCode == sourceLanguageCode &&
        other.publishedSteamId == publishedSteamId;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      modSteamId.hashCode ^
      modVersion.hashCode ^
      gameInstallationId.hashCode ^
      sourceFilePath.hashCode ^
      outputFilePath.hashCode ^
      lastUpdateCheck.hashCode ^
      sourceModUpdated.hashCode ^
      batchSize.hashCode ^
      parallelBatches.hashCode ^
      customPrompt.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      completedAt.hashCode ^
      metadata.hashCode ^
      hasModUpdateImpact.hashCode ^
      projectType.hashCode ^
      sourceLanguageCode.hashCode ^
      publishedSteamId.hashCode;

  @override
  String toString() => 'Project(id: $id, name: $name, type: $projectType, gameInstallationId: $gameInstallationId)';
}

/// Convert SQLite integer (0/1) to bool for hasModUpdateImpact field
bool _boolFromInt(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is int) return value == 1;
  return false;
}

/// Convert bool to SQLite integer (0/1) for hasModUpdateImpact field
int _boolToInt(bool value) => value ? 1 : 0;
