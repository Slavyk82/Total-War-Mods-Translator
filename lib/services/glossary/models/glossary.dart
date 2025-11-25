import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'glossary.g.dart';

/// Represents a glossary containing terminology translations
///
/// Glossaries can be global (shared across all projects) or project-specific.
@JsonSerializable()
class Glossary {
  /// Unique glossary ID (UUID)
  final String id;

  /// Glossary name (unique)
  final String name;

  /// Optional description
  final String? description;

  /// If true, glossary is shared across all projects
  @JsonKey(name: 'is_global')
  @BoolIntConverter()
  final bool isGlobal;

  /// If specified, glossary is project-specific
  @JsonKey(name: 'project_id')
  final String? projectId;

  /// Target language ID (required by database schema)
  @JsonKey(name: 'target_language_id')
  final String? targetLanguageId;

  /// Number of entries in the glossary (calculated dynamically)
  @JsonKey(includeToJson: false)
  final int entryCount;

  /// Creation timestamp (Unix milliseconds)
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Last modification timestamp (Unix milliseconds)
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const Glossary({
    required this.id,
    required this.name,
    this.description,
    required this.isGlobal,
    this.projectId,
    this.targetLanguageId,
    this.entryCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON serialization
  factory Glossary.fromJson(Map<String, dynamic> json) =>
      _$GlossaryFromJson(json);

  Map<String, dynamic> toJson() => _$GlossaryToJson(this);

  // copyWith method for immutability
  Glossary copyWith({
    String? id,
    String? name,
    String? description,
    bool? isGlobal,
    String? projectId,
    String? targetLanguageId,
    int? entryCount,
    int? createdAt,
    int? updatedAt,
  }) {
    return Glossary(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      isGlobal: isGlobal ?? this.isGlobal,
      projectId: projectId ?? this.projectId,
      targetLanguageId: targetLanguageId ?? this.targetLanguageId,
      entryCount: entryCount ?? this.entryCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Glossary &&
        other.id == id &&
        other.name == name &&
        other.description == description &&
        other.isGlobal == isGlobal &&
        other.projectId == projectId &&
        other.targetLanguageId == targetLanguageId &&
        other.entryCount == entryCount &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      name,
      description,
      isGlobal,
      projectId,
      targetLanguageId,
      entryCount,
      createdAt,
      updatedAt,
    );
  }

  @override
  String toString() {
    return 'Glossary(id: $id, name: $name, description: $description, '
        'isGlobal: $isGlobal, projectId: $projectId, targetLanguageId: $targetLanguageId, '
        'entryCount: $entryCount, createdAt: $createdAt, updatedAt: $updatedAt)';
  }
}
