import 'package:json_annotation/json_annotation.dart';

part 'llm_model_info.g.dart';

/// Information about an available LLM model
@JsonSerializable()
class LlmModelInfo {
  /// Model identifier (e.g., "claude-3-5-sonnet-20241022", "gpt-4-turbo")
  final String id;

  /// Display name for the model (optional)
  final String? displayName;

  /// When the model was created (optional)
  final DateTime? createdAt;

  /// Model type (optional, e.g., "model")
  final String? type;

  /// Organization that owns the model (optional, OpenAI specific)
  final String? ownedBy;

  const LlmModelInfo({
    required this.id,
    this.displayName,
    this.createdAt,
    this.type,
    this.ownedBy,
  });

  factory LlmModelInfo.fromJson(Map<String, dynamic> json) =>
      _$LlmModelInfoFromJson(json);

  Map<String, dynamic> toJson() => _$LlmModelInfoToJson(this);

  /// Get a user-friendly display name for the model
  String get friendlyName => displayName ?? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmModelInfo &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'LlmModelInfo(id: $id, displayName: $displayName, createdAt: $createdAt)';
  }
}
