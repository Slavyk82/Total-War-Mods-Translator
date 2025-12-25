// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_context.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationContext _$TranslationContextFromJson(Map<String, dynamic> json) =>
    TranslationContext(
      id: json['id'] as String,
      projectId: json['projectId'] as String,
      projectLanguageId: json['projectLanguageId'] as String,
      providerId: json['providerId'] as String?,
      modelId: json['modelId'] as String?,
      gameContext: json['gameContext'] as String?,
      projectContext: json['projectContext'] as String?,
      glossaryTerms: (json['glossaryTerms'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ),
      glossaryId: json['glossaryId'] as String?,
      sourceLanguage: json['sourceLanguage'] as String?,
      fewShotExamples: (json['fewShotExamples'] as List<dynamic>?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
      customInstructions: json['customInstructions'] as String?,
      targetLanguage: json['targetLanguage'] as String,
      category: json['category'] as String?,
      formalityLevel: json['formalityLevel'] as String?,
      preserveFormatting: json['preserveFormatting'] as bool? ?? true,
      unitsPerBatch: (json['unitsPerBatch'] as num?)?.toInt() ?? 100,
      parallelBatches: (json['parallelBatches'] as num?)?.toInt() ?? 1,
      skipTranslationMemory: json['skipTranslationMemory'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$TranslationContextToJson(TranslationContext instance) =>
    <String, dynamic>{
      'id': instance.id,
      'projectId': instance.projectId,
      'projectLanguageId': instance.projectLanguageId,
      'providerId': instance.providerId,
      'modelId': instance.modelId,
      'gameContext': instance.gameContext,
      'projectContext': instance.projectContext,
      'glossaryTerms': instance.glossaryTerms,
      'glossaryId': instance.glossaryId,
      'sourceLanguage': instance.sourceLanguage,
      'fewShotExamples': instance.fewShotExamples,
      'customInstructions': instance.customInstructions,
      'targetLanguage': instance.targetLanguage,
      'category': instance.category,
      'formalityLevel': instance.formalityLevel,
      'preserveFormatting': instance.preserveFormatting,
      'unitsPerBatch': instance.unitsPerBatch,
      'parallelBatches': instance.parallelBatches,
      'skipTranslationMemory': instance.skipTranslationMemory,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
