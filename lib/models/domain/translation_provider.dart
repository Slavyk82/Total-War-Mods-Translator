import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/models/common/json_converters.dart';

part 'translation_provider.g.dart';

/// Represents a translation service provider (e.g., Anthropic Claude, OpenAI, DeepL).
///
/// Translation providers are external services that perform the actual translation work.
/// Each provider has different capabilities, rate limits, and configuration requirements.
@JsonSerializable()
class TranslationProvider {
  /// Unique identifier (UUID)
  final String id;

  /// Provider code (e.g., 'anthropic', 'openai', 'deepl')
  final String code;

  /// Provider display name (e.g., 'Anthropic Claude', 'OpenAI GPT')
  final String name;

  /// API endpoint URL
  @JsonKey(name: 'api_endpoint')
  final String? apiEndpoint;

  /// Default model to use (e.g., 'claude-3-5-sonnet-20241022', 'gpt-4-turbo-preview')
  @JsonKey(name: 'default_model')
  final String? defaultModel;

  /// Maximum context tokens the model supports
  @JsonKey(name: 'max_context_tokens')
  final int? maxContextTokens;

  /// Maximum number of translation units per batch
  @JsonKey(name: 'max_batch_size')
  final int maxBatchSize;

  /// Rate limit: requests per minute
  @JsonKey(name: 'rate_limit_rpm')
  final int? rateLimitRpm;

  /// Rate limit: tokens per minute
  @JsonKey(name: 'rate_limit_tpm')
  final int? rateLimitTpm;

  /// Whether this provider is currently active/enabled
  @JsonKey(name: 'is_active')
  @BoolIntConverter()
  final bool isActive;

  /// Unix timestamp when the provider was created
  @JsonKey(name: 'created_at')
  final int createdAt;

  const TranslationProvider({
    required this.id,
    required this.code,
    required this.name,
    this.apiEndpoint,
    this.defaultModel,
    this.maxContextTokens,
    this.maxBatchSize = 30,
    this.rateLimitRpm,
    this.rateLimitTpm,
    this.isActive = true,
    required this.createdAt,
  });

  /// Returns true if the provider is currently active
  bool get isEnabled => isActive;

  /// Returns true if the provider has rate limiting configured
  bool get hasRateLimits => rateLimitRpm != null || rateLimitTpm != null;

  /// Returns true if the provider has context token limits
  bool get hasContextLimit => maxContextTokens != null && maxContextTokens! > 0;

  /// Returns a display string with provider name and model
  String get displayNameWithModel {
    if (defaultModel != null) {
      return '$name ($defaultModel)';
    }
    return name;
  }

  /// Creates a copy with optional new values
  TranslationProvider copyWith({
    String? id,
    String? code,
    String? name,
    String? apiEndpoint,
    String? defaultModel,
    int? maxContextTokens,
    int? maxBatchSize,
    int? rateLimitRpm,
    int? rateLimitTpm,
    bool? isActive,
    int? createdAt,
  }) {
    return TranslationProvider(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      apiEndpoint: apiEndpoint ?? this.apiEndpoint,
      defaultModel: defaultModel ?? this.defaultModel,
      maxContextTokens: maxContextTokens ?? this.maxContextTokens,
      maxBatchSize: maxBatchSize ?? this.maxBatchSize,
      rateLimitRpm: rateLimitRpm ?? this.rateLimitRpm,
      rateLimitTpm: rateLimitTpm ?? this.rateLimitTpm,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory TranslationProvider.fromJson(Map<String, dynamic> json) =>
      _$TranslationProviderFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationProviderToJson(this);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TranslationProvider &&
        other.id == id &&
        other.code == code &&
        other.name == name &&
        other.apiEndpoint == apiEndpoint &&
        other.defaultModel == defaultModel &&
        other.maxContextTokens == maxContextTokens &&
        other.maxBatchSize == maxBatchSize &&
        other.rateLimitRpm == rateLimitRpm &&
        other.rateLimitTpm == rateLimitTpm &&
        other.isActive == isActive &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      code.hashCode ^
      name.hashCode ^
      apiEndpoint.hashCode ^
      defaultModel.hashCode ^
      maxContextTokens.hashCode ^
      maxBatchSize.hashCode ^
      rateLimitRpm.hashCode ^
      rateLimitTpm.hashCode ^
      isActive.hashCode ^
      createdAt.hashCode;

  @override
  String toString() {
    return 'TranslationProvider(id: $id, code: $code, name: $name, apiEndpoint: $apiEndpoint, defaultModel: $defaultModel, maxContextTokens: $maxContextTokens, maxBatchSize: $maxBatchSize, rateLimitRpm: $rateLimitRpm, rateLimitTpm: $rateLimitTpm, isActive: $isActive, createdAt: $createdAt)';
  }
}
