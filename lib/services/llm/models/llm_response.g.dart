// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_response.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlmResponse _$LlmResponseFromJson(Map<String, dynamic> json) => LlmResponse(
  requestId: json['requestId'] as String,
  translations: Map<String, String>.from(json['translations'] as Map),
  providerCode: json['providerCode'] as String,
  modelName: json['modelName'] as String,
  inputTokens: (json['inputTokens'] as num).toInt(),
  outputTokens: (json['outputTokens'] as num).toInt(),
  totalTokens: (json['totalTokens'] as num).toInt(),
  processingTimeMs: (json['processingTimeMs'] as num).toInt(),
  timestamp: DateTime.parse(json['timestamp'] as String),
  finishReason: json['finishReason'] as String?,
  warnings: (json['warnings'] as List<dynamic>?)
      ?.map((e) => e as String)
      .toList(),
);

Map<String, dynamic> _$LlmResponseToJson(LlmResponse instance) =>
    <String, dynamic>{
      'requestId': instance.requestId,
      'translations': instance.translations,
      'providerCode': instance.providerCode,
      'modelName': instance.modelName,
      'inputTokens': instance.inputTokens,
      'outputTokens': instance.outputTokens,
      'totalTokens': instance.totalTokens,
      'processingTimeMs': instance.processingTimeMs,
      'timestamp': instance.timestamp.toIso8601String(),
      'finishReason': instance.finishReason,
      'warnings': instance.warnings,
    };

BatchTranslationResult _$BatchTranslationResultFromJson(
  Map<String, dynamic> json,
) => BatchTranslationResult(
  batchId: json['batchId'] as String,
  totalUnits: (json['totalUnits'] as num).toInt(),
  successfulUnits: (json['successfulUnits'] as num).toInt(),
  failedUnits: (json['failedUnits'] as num).toInt(),
  responses: (json['responses'] as List<dynamic>)
      .map((e) => LlmResponse.fromJson(e as Map<String, dynamic>))
      .toList(),
  errors: Map<String, String>.from(json['errors'] as Map),
  totalTokens: (json['totalTokens'] as num).toInt(),
  totalProcessingTimeMs: (json['totalProcessingTimeMs'] as num).toInt(),
  startTime: DateTime.parse(json['startTime'] as String),
  endTime: DateTime.parse(json['endTime'] as String),
);

Map<String, dynamic> _$BatchTranslationResultToJson(
  BatchTranslationResult instance,
) => <String, dynamic>{
  'batchId': instance.batchId,
  'totalUnits': instance.totalUnits,
  'successfulUnits': instance.successfulUnits,
  'failedUnits': instance.failedUnits,
  'responses': instance.responses,
  'errors': instance.errors,
  'totalTokens': instance.totalTokens,
  'totalProcessingTimeMs': instance.totalProcessingTimeMs,
  'startTime': instance.startTime.toIso8601String(),
  'endTime': instance.endTime.toIso8601String(),
};
