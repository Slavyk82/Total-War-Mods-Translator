// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlmRequest _$LlmRequestFromJson(Map<String, dynamic> json) => LlmRequest(
  requestId: json['requestId'] as String,
  targetLanguage: json['targetLanguage'] as String,
  texts: Map<String, String>.from(json['texts'] as Map),
  systemPrompt: json['systemPrompt'] as String,
  gameContext: json['gameContext'] as String?,
  projectContext: json['projectContext'] as String?,
  fewShotExamples: (json['fewShotExamples'] as List<dynamic>?)
      ?.map((e) => TranslationExample.fromJson(e as Map<String, dynamic>))
      .toList(),
  glossaryTerms: (json['glossaryTerms'] as Map<String, dynamic>?)?.map(
    (k, e) => MapEntry(k, e as String),
  ),
  modelName: json['modelName'] as String?,
  providerCode: json['providerCode'] as String?,
  temperature: (json['temperature'] as num?)?.toDouble() ?? 0.3,
  maxTokens: (json['maxTokens'] as num?)?.toInt(),
  timestamp: DateTime.parse(json['timestamp'] as String),
);

Map<String, dynamic> _$LlmRequestToJson(LlmRequest instance) =>
    <String, dynamic>{
      'requestId': instance.requestId,
      'targetLanguage': instance.targetLanguage,
      'texts': instance.texts,
      'systemPrompt': instance.systemPrompt,
      'gameContext': instance.gameContext,
      'projectContext': instance.projectContext,
      'fewShotExamples': instance.fewShotExamples,
      'glossaryTerms': instance.glossaryTerms,
      'modelName': instance.modelName,
      'providerCode': instance.providerCode,
      'temperature': instance.temperature,
      'maxTokens': instance.maxTokens,
      'timestamp': instance.timestamp.toIso8601String(),
    };

TranslationExample _$TranslationExampleFromJson(Map<String, dynamic> json) =>
    TranslationExample(
      source: json['source'] as String,
      target: json['target'] as String,
      similarityScore: (json['similarityScore'] as num?)?.toDouble(),
    );

Map<String, dynamic> _$TranslationExampleToJson(TranslationExample instance) =>
    <String, dynamic>{
      'source': instance.source,
      'target': instance.target,
      'similarityScore': instance.similarityScore,
    };
