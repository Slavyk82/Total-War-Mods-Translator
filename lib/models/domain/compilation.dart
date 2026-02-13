import 'package:json_annotation/json_annotation.dart';

part 'compilation.g.dart';

/// Represents a pack compilation configuration.
///
/// A compilation groups multiple projects together to generate
/// a single combined .pack file for distribution.
@JsonSerializable()
class Compilation {
  /// Unique identifier (UUID)
  final String id;

  /// Compilation name
  final String name;

  /// Prefix for the pack filename (e.g., "!!!!!!!!!!_FR_Compilation_")
  final String prefix;

  /// Pack name without prefix and extension (e.g., "my_translations")
  @JsonKey(name: 'pack_name')
  final String packName;

  /// ID of the associated game installation
  @JsonKey(name: 'game_installation_id')
  final String gameInstallationId;

  /// ID of the target language for this compilation
  @JsonKey(name: 'language_id')
  final String? languageId;

  /// Path to the last generated pack file
  @JsonKey(name: 'last_output_path')
  final String? lastOutputPath;

  /// Unix timestamp when the compilation was last generated
  @JsonKey(name: 'last_generated_at')
  final int? lastGeneratedAt;

  /// Unix timestamp when the compilation was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Steam Workshop published file ID (after publishing)
  @JsonKey(name: 'published_steam_id')
  final String? publishedSteamId;

  /// Unix timestamp when published to Steam Workshop
  @JsonKey(name: 'published_at')
  final int? publishedAt;

  /// Unix timestamp when the compilation was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const Compilation({
    required this.id,
    required this.name,
    required this.prefix,
    required this.packName,
    required this.gameInstallationId,
    this.languageId,
    this.lastOutputPath,
    this.lastGeneratedAt,
    this.publishedSteamId,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Build the full pack filename (lowercase enforced)
  String get fullPackFileName => '$prefix$packName.pack'.toLowerCase();

  /// Check if the compilation has been generated at least once
  bool get hasBeenGenerated => lastGeneratedAt != null;

  Compilation copyWith({
    String? id,
    String? name,
    String? prefix,
    String? packName,
    String? gameInstallationId,
    String? languageId,
    String? lastOutputPath,
    int? lastGeneratedAt,
    String? publishedSteamId,
    int? publishedAt,
    int? createdAt,
    int? updatedAt,
  }) {
    return Compilation(
      id: id ?? this.id,
      name: name ?? this.name,
      prefix: prefix ?? this.prefix,
      packName: packName ?? this.packName,
      gameInstallationId: gameInstallationId ?? this.gameInstallationId,
      languageId: languageId ?? this.languageId,
      lastOutputPath: lastOutputPath ?? this.lastOutputPath,
      lastGeneratedAt: lastGeneratedAt ?? this.lastGeneratedAt,
      publishedSteamId: publishedSteamId ?? this.publishedSteamId,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Compilation.fromJson(Map<String, dynamic> json) =>
      _$CompilationFromJson(json);

  Map<String, dynamic> toJson() => _$CompilationToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Compilation &&
        other.id == id &&
        other.name == name &&
        other.prefix == prefix &&
        other.packName == packName &&
        other.gameInstallationId == gameInstallationId &&
        other.languageId == languageId &&
        other.lastOutputPath == lastOutputPath &&
        other.lastGeneratedAt == lastGeneratedAt &&
        other.publishedSteamId == publishedSteamId &&
        other.publishedAt == publishedAt &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      prefix.hashCode ^
      packName.hashCode ^
      gameInstallationId.hashCode ^
      languageId.hashCode ^
      lastOutputPath.hashCode ^
      lastGeneratedAt.hashCode ^
      publishedSteamId.hashCode ^
      publishedAt.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode;

  @override
  String toString() =>
      'Compilation(id: $id, name: $name, packName: $fullPackFileName)';
}

/// Represents a project included in a compilation.
@JsonSerializable()
class CompilationProject {
  /// Unique identifier (UUID)
  final String id;

  /// ID of the compilation
  @JsonKey(name: 'compilation_id')
  final String compilationId;

  /// ID of the project
  @JsonKey(name: 'project_id')
  final String projectId;

  /// Order in the compilation (for deterministic pack generation)
  @JsonKey(name: 'sort_order')
  final int sortOrder;

  /// Unix timestamp when added to compilation
  @JsonKey(name: 'added_at')
  final int addedAt;

  const CompilationProject({
    required this.id,
    required this.compilationId,
    required this.projectId,
    required this.sortOrder,
    required this.addedAt,
  });

  CompilationProject copyWith({
    String? id,
    String? compilationId,
    String? projectId,
    int? sortOrder,
    int? addedAt,
  }) {
    return CompilationProject(
      id: id ?? this.id,
      compilationId: compilationId ?? this.compilationId,
      projectId: projectId ?? this.projectId,
      sortOrder: sortOrder ?? this.sortOrder,
      addedAt: addedAt ?? this.addedAt,
    );
  }

  factory CompilationProject.fromJson(Map<String, dynamic> json) =>
      _$CompilationProjectFromJson(json);

  Map<String, dynamic> toJson() => _$CompilationProjectToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CompilationProject &&
        other.id == id &&
        other.compilationId == compilationId &&
        other.projectId == projectId &&
        other.sortOrder == sortOrder &&
        other.addedAt == addedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      compilationId.hashCode ^
      projectId.hashCode ^
      sortOrder.hashCode ^
      addedAt.hashCode;

  @override
  String toString() =>
      'CompilationProject(compilationId: $compilationId, projectId: $projectId)';
}
