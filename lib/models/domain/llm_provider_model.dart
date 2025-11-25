import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'llm_provider_model.g.dart';

/// Represents an LLM model available from a specific provider.
///
/// Models are fetched from provider APIs (Anthropic, OpenAI, etc.) and stored
/// locally for persistence and selection. Users can enable/disable models,
/// set a default model per provider, and models can be archived when they
/// become unavailable from the provider.
///
/// The model tracks:
/// - Provider association (anthropic, openai, deepl)
/// - Model identification and display information
/// - Enabled/disabled status for user selection
/// - Default model designation per provider
/// - Archival status for deprecated models
/// - Timestamps for tracking model lifecycle
@JsonSerializable()
class LlmProviderModel {
  /// Unique identifier (UUID)
  final String id;

  /// Provider code (e.g., 'anthropic', 'openai', 'deepl')
  @JsonKey(name: 'provider_code')
  final String providerCode;

  /// Model identifier from the provider's API (e.g., 'claude-3-5-sonnet-20241022')
  @JsonKey(name: 'model_id')
  final String modelId;

  /// Optional display name for the model
  @JsonKey(name: 'display_name')
  final String? displayName;

  /// Whether this model is enabled for use
  ///
  /// Only enabled models appear in selection dropdowns during translation.
  /// Archived models cannot be enabled.
  @JsonKey(name: 'is_enabled')
  @BoolIntConverter()
  final bool isEnabled;

  /// Whether this is the default model for the provider
  ///
  /// Each provider should have exactly one default model.
  /// The database trigger ensures this constraint.
  /// Archived models cannot be set as default.
  @JsonKey(name: 'is_default')
  @BoolIntConverter()
  final bool isDefault;

  /// Whether this model has been archived
  ///
  /// Models are automatically archived when they're no longer returned
  /// by the provider's API during model fetching. Archived models:
  /// - Cannot be enabled or set as default
  /// - Are hidden from user selection
  /// - Remain in database for historical reference
  @JsonKey(name: 'is_archived')
  @BoolIntConverter()
  final bool isArchived;

  /// Unix timestamp when this record was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  /// Unix timestamp when this record was last updated
  @JsonKey(name: 'updated_at')
  final int updatedAt;

  /// Unix timestamp when this model was last fetched from the provider API
  ///
  /// Used to determine which models should be archived (models not seen
  /// in recent API responses).
  @JsonKey(name: 'last_fetched_at')
  final int lastFetchedAt;

  const LlmProviderModel({
    required this.id,
    required this.providerCode,
    required this.modelId,
    this.displayName,
    this.isEnabled = false,
    this.isDefault = false,
    this.isArchived = false,
    required this.createdAt,
    required this.updatedAt,
    required this.lastFetchedAt,
  });

  /// Returns the display name or model ID if display name is not set
  String get friendlyName => displayName ?? modelId;

  /// Returns true if this model is available for use (not archived)
  bool get isAvailable => !isArchived;

  /// Returns true if this model can be enabled
  ///
  /// A model can be enabled if it's not archived.
  bool get canBeEnabled => !isArchived;

  /// Returns true if this model can be set as default
  ///
  /// A model can be set as default if it's not archived.
  bool get canBeDefault => !isArchived;

  /// Creates a copy of this model with the given fields replaced
  LlmProviderModel copyWith({
    String? id,
    String? providerCode,
    String? modelId,
    String? displayName,
    bool? isEnabled,
    bool? isDefault,
    bool? isArchived,
    int? createdAt,
    int? updatedAt,
    int? lastFetchedAt,
  }) {
    return LlmProviderModel(
      id: id ?? this.id,
      providerCode: providerCode ?? this.providerCode,
      modelId: modelId ?? this.modelId,
      displayName: displayName ?? this.displayName,
      isEnabled: isEnabled ?? this.isEnabled,
      isDefault: isDefault ?? this.isDefault,
      isArchived: isArchived ?? this.isArchived,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastFetchedAt: lastFetchedAt ?? this.lastFetchedAt,
    );
  }

  /// Creates a LlmProviderModel from JSON
  factory LlmProviderModel.fromJson(Map<String, dynamic> json) =>
      _$LlmProviderModelFromJson(json);

  /// Converts this LlmProviderModel to JSON
  Map<String, dynamic> toJson() => _$LlmProviderModelToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LlmProviderModel &&
        other.id == id &&
        other.providerCode == providerCode &&
        other.modelId == modelId &&
        other.displayName == displayName &&
        other.isEnabled == isEnabled &&
        other.isDefault == isDefault &&
        other.isArchived == isArchived &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.lastFetchedAt == lastFetchedAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      providerCode.hashCode ^
      modelId.hashCode ^
      (displayName?.hashCode ?? 0) ^
      isEnabled.hashCode ^
      isDefault.hashCode ^
      isArchived.hashCode ^
      createdAt.hashCode ^
      updatedAt.hashCode ^
      lastFetchedAt.hashCode;

  @override
  String toString() {
    return 'LlmProviderModel('
        'id: $id, '
        'providerCode: $providerCode, '
        'modelId: $modelId, '
        'displayName: $displayName, '
        'isEnabled: $isEnabled, '
        'isDefault: $isDefault, '
        'isArchived: $isArchived, '
        'createdAt: $createdAt, '
        'updatedAt: $updatedAt, '
        'lastFetchedAt: $lastFetchedAt'
        ')';
  }
}
