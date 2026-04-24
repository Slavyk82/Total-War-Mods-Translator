import 'package:json_annotation/json_annotation.dart';

part 'glossary.g.dart';

/// A game-scoped glossary, uniquely identified by (gameCode, targetLanguageId).
@JsonSerializable()
class Glossary {
  final String id;
  final String name;
  final String? description;

  @JsonKey(name: 'game_code')
  final String gameCode;

  @JsonKey(name: 'target_language_id')
  final String targetLanguageId;

  @JsonKey(includeToJson: false)
  final int entryCount;

  @JsonKey(name: 'created_at')
  final int createdAt;

  @JsonKey(name: 'updated_at')
  final int updatedAt;

  const Glossary({
    required this.id,
    required this.name,
    this.description,
    required this.gameCode,
    required this.targetLanguageId,
    this.entryCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Glossary.fromJson(Map<String, dynamic> json) =>
      _$GlossaryFromJson(json);

  Map<String, dynamic> toJson() => _$GlossaryToJson(this);

  Glossary copyWith({
    String? id,
    String? name,
    String? description,
    String? gameCode,
    String? targetLanguageId,
    int? entryCount,
    int? createdAt,
    int? updatedAt,
  }) =>
      Glossary(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        gameCode: gameCode ?? this.gameCode,
        targetLanguageId: targetLanguageId ?? this.targetLanguageId,
        entryCount: entryCount ?? this.entryCount,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Glossary &&
          other.id == id &&
          other.name == name &&
          other.description == description &&
          other.gameCode == gameCode &&
          other.targetLanguageId == targetLanguageId &&
          other.entryCount == entryCount &&
          other.createdAt == createdAt &&
          other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, description, gameCode,
      targetLanguageId, entryCount, createdAt, updatedAt);

  @override
  String toString() =>
      'Glossary(id: $id, name: $name, gameCode: $gameCode, targetLanguageId: $targetLanguageId, entryCount: $entryCount)';
}
