import 'package:json_annotation/json_annotation.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';

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

  /// @deprecated Use [glossaryEntries] instead for variant support
  /// Legacy glossary terms (term -> translation)
  final Map<String, String>? glossaryTerms;

  /// Full glossary entries with variant support
  /// Filtered per-batch during prompt building to optimize tokens
  @JsonKey(includeFromJson: false, includeToJson: false)
  final List<GlossaryTermWithVariants>? glossaryEntries;

  /// Glossary ID for DeepL sync
  /// Used to sync glossary to DeepL servers before translation
  final String? glossaryId;

  /// Source language code (ISO 639-1)
  /// Required for DeepL glossary sync
  final String? sourceLanguage;

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

  /// Number of units per LLM batch (default: 100)
  final int unitsPerBatch;

  /// Number of parallel LLM batches (default: 1)
  /// Note: Higher values can improve throughput but may cause FTS5 corruption
  /// due to concurrent database writes. Keep at 1 for stability.
  final int parallelBatches;

  /// Skip Translation Memory lookup during translation
  /// When true, all units are sent directly to LLM without TM matching
  final bool skipTranslationMemory;

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
    this.glossaryEntries,
    this.glossaryId,
    this.sourceLanguage,
    this.fewShotExamples,
    this.customInstructions,
    required this.targetLanguage,
    this.category,
    this.formalityLevel,
    this.preserveFormatting = true,
    this.unitsPerBatch = 100,
    this.parallelBatches = 1,
    this.skipTranslationMemory = false,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Extracts the provider code from providerId.
  /// 
  /// providerId format is "provider_<code>" (e.g., "provider_anthropic").
  /// Returns the code part (e.g., "anthropic"), or null if providerId is null/invalid.
  String? get providerCode {
    if (providerId == null) return null;
    if (providerId!.startsWith('provider_')) {
      return providerId!.substring('provider_'.length);
    }
    // If providerId doesn't have the prefix, assume it's already the code
    return providerId;
  }

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
    List<GlossaryTermWithVariants>? glossaryEntries,
    String? glossaryId,
    String? sourceLanguage,
    List<Map<String, String>>? fewShotExamples,
    String? customInstructions,
    String? targetLanguage,
    String? category,
    String? formalityLevel,
    bool? preserveFormatting,
    bool? skipTranslationMemory,
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
      glossaryEntries: glossaryEntries ?? this.glossaryEntries,
      glossaryId: glossaryId ?? this.glossaryId,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      fewShotExamples: fewShotExamples ?? this.fewShotExamples,
      customInstructions: customInstructions ?? this.customInstructions,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      category: category ?? this.category,
      formalityLevel: formalityLevel ?? this.formalityLevel,
      preserveFormatting: preserveFormatting ?? this.preserveFormatting,
      skipTranslationMemory: skipTranslationMemory ?? this.skipTranslationMemory,
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
