import 'package:json_annotation/json_annotation.dart';

part 'llm_request.g.dart';

/// Request for LLM translation
@JsonSerializable()
class LlmRequest {
  /// Unique identifier for this request
  final String requestId;

  /// Target language code (ISO 639-1)
  final String targetLanguage;

  /// Texts to translate (key-value pairs)
  final Map<String, String> texts;

  /// System prompt (role, rules, format)
  final String systemPrompt;

  /// Game-specific context (optional)
  final String? gameContext;

  /// Project-specific context (optional)
  final String? projectContext;

  /// Few-shot examples from Translation Memory (optional)
  final List<TranslationExample>? fewShotExamples;

  /// Glossary terms to preserve (optional)
  final Map<String, String>? glossaryTerms;

  /// Model name to use (e.g., "claude-3-5-sonnet-20241022")
  final String? modelName;

  /// Temperature (0.0-1.0, default 0.3 for consistency)
  final double temperature;

  /// Maximum tokens for response
  final int? maxTokens;

  /// Request timestamp
  final DateTime timestamp;

  const LlmRequest({
    required this.requestId,
    required this.targetLanguage,
    required this.texts,
    required this.systemPrompt,
    this.gameContext,
    this.projectContext,
    this.fewShotExamples,
    this.glossaryTerms,
    this.modelName,
    this.temperature = 0.3,
    this.maxTokens,
    required this.timestamp,
  });

  factory LlmRequest.fromJson(Map<String, dynamic> json) =>
      _$LlmRequestFromJson(json);

  Map<String, dynamic> toJson() => _$LlmRequestToJson(this);

  LlmRequest copyWith({
    String? requestId,
    String? targetLanguage,
    Map<String, String>? texts,
    String? systemPrompt,
    String? gameContext,
    String? projectContext,
    List<TranslationExample>? fewShotExamples,
    Map<String, String>? glossaryTerms,
    String? modelName,
    double? temperature,
    int? maxTokens,
    DateTime? timestamp,
  }) {
    return LlmRequest(
      requestId: requestId ?? this.requestId,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      texts: texts ?? this.texts,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      gameContext: gameContext ?? this.gameContext,
      projectContext: projectContext ?? this.projectContext,
      fewShotExamples: fewShotExamples ?? this.fewShotExamples,
      glossaryTerms: glossaryTerms ?? this.glossaryTerms,
      modelName: modelName ?? this.modelName,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmRequest &&
          runtimeType == other.runtimeType &&
          requestId == other.requestId &&
          targetLanguage == other.targetLanguage &&
          texts == other.texts &&
          systemPrompt == other.systemPrompt &&
          gameContext == other.gameContext &&
          projectContext == other.projectContext &&
          fewShotExamples == other.fewShotExamples &&
          glossaryTerms == other.glossaryTerms &&
          modelName == other.modelName &&
          temperature == other.temperature &&
          maxTokens == other.maxTokens &&
          timestamp == other.timestamp;

  @override
  int get hashCode =>
      requestId.hashCode ^
      targetLanguage.hashCode ^
      texts.hashCode ^
      systemPrompt.hashCode ^
      (gameContext?.hashCode ?? 0) ^
      (projectContext?.hashCode ?? 0) ^
      (fewShotExamples?.hashCode ?? 0) ^
      (glossaryTerms?.hashCode ?? 0) ^
      (modelName?.hashCode ?? 0) ^
      temperature.hashCode ^
      (maxTokens?.hashCode ?? 0) ^
      timestamp.hashCode;

  @override
  String toString() {
    return 'LlmRequest(requestId: $requestId, '
        'targetLanguage: $targetLanguage, texts: ${texts.length} items, '
        'temperature: $temperature, timestamp: $timestamp)';
  }
}

/// Translation example for few-shot learning
@JsonSerializable()
class TranslationExample {
  /// Source text
  final String source;

  /// Translated text
  final String target;

  /// Similarity score (0.0-1.0) if from fuzzy match
  final double? similarityScore;

  const TranslationExample({
    required this.source,
    required this.target,
    this.similarityScore,
  });

  factory TranslationExample.fromJson(Map<String, dynamic> json) =>
      _$TranslationExampleFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationExampleToJson(this);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationExample &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          target == other.target &&
          similarityScore == other.similarityScore;

  @override
  int get hashCode =>
      source.hashCode ^ target.hashCode ^ (similarityScore?.hashCode ?? 0);

  @override
  String toString() {
    return 'TranslationExample(source: $source, target: $target, '
        'similarityScore: $similarityScore)';
  }
}
