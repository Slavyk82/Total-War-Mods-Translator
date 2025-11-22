import 'package:json_annotation/json_annotation.dart';

part 'translation_context.g.dart';

/// Context information for translation requests
/// Includes game-specific, project-specific, and glossary context
@JsonSerializable()
class TranslationContext {
  /// Unique identifier
  final String id;

  /// Project ID this context belongs to
  final String projectId;

  /// Project-Language ID (unique identifier for project-language pair)
  final String projectLanguageId;

  /// LLM Provider ID (e.g., 'anthropic', 'openai')
  final String? providerId;

  /// LLM Model ID (e.g., 'claude-haiku-4.5', 'gpt-4-turbo')
  final String? modelId;

  /// Game-specific context (lore, universe, tone)
  final String? gameContext;

  /// Project-specific context (mod type, faction, period)
  final String? projectContext;

  /// Glossary terms to preserve (term -> translation)
  final Map<String, String>? glossaryTerms;

  /// Few-shot examples from Translation Memory
  /// Format: [{"source": "...", "target": "..."}]
  final List<Map<String, String>>? fewShotExamples;

  /// Additional instructions for the LLM
  final String? customInstructions;

  /// Target language code (ISO 639-1)
  final String targetLanguage;

  /// Category of content (UI, narrative, tutorial, etc.)
  final String? category;

  /// Formality level (formal, informal, neutral)
  final String? formalityLevel;

  /// Preserve formatting (XML tags, BBCode, etc.)
  final bool preserveFormatting;

  /// Created timestamp
  final DateTime createdAt;

  /// Updated timestamp
  final DateTime updatedAt;

  const TranslationContext({
    required this.id,
    required this.projectId,
    required this.projectLanguageId,
    this.providerId,
    this.modelId,
    this.gameContext,
    this.projectContext,
    this.glossaryTerms,
    this.fewShotExamples,
    this.customInstructions,
    required this.targetLanguage,
    this.category,
    this.formalityLevel,
    this.preserveFormatting = true,
    required this.createdAt,
    required this.updatedAt,
  });

  // JSON serialization
  factory TranslationContext.fromJson(Map<String, dynamic> json) =>
      _$TranslationContextFromJson(json);

  Map<String, dynamic> toJson() => _$TranslationContextToJson(this);

  // CopyWith method
  TranslationContext copyWith({
    String? id,
    String? projectId,
    String? projectLanguageId,
    String? providerId,
    String? modelId,
    String? gameContext,
    String? projectContext,
    Map<String, String>? glossaryTerms,
    List<Map<String, String>>? fewShotExamples,
    String? customInstructions,
    String? targetLanguage,
    String? category,
    String? formalityLevel,
    bool? preserveFormatting,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return TranslationContext(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      projectLanguageId: projectLanguageId ?? this.projectLanguageId,
      providerId: providerId ?? this.providerId,
      modelId: modelId ?? this.modelId,
      gameContext: gameContext ?? this.gameContext,
      projectContext: projectContext ?? this.projectContext,
      glossaryTerms: glossaryTerms ?? this.glossaryTerms,
      fewShotExamples: fewShotExamples ?? this.fewShotExamples,
      customInstructions: customInstructions ?? this.customInstructions,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      category: category ?? this.category,
      formalityLevel: formalityLevel ?? this.formalityLevel,
      preserveFormatting: preserveFormatting ?? this.preserveFormatting,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TranslationContext &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          projectId == other.projectId &&
          projectLanguageId == other.projectLanguageId &&
          gameContext == other.gameContext &&
          projectContext == other.projectContext &&
          targetLanguage == other.targetLanguage;

  @override
  int get hashCode =>
      id.hashCode ^
      projectId.hashCode ^
      projectLanguageId.hashCode ^
      targetLanguage.hashCode;

  @override
  String toString() {
    return 'TranslationContext(id: $id, projectId: $projectId, '
        'projectLanguageId: $projectLanguageId, '
        'targetLanguage: $targetLanguage, '
        'category: $category)';
  }
}
