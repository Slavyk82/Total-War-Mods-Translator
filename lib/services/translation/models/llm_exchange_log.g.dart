// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_exchange_log.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlmExchangeLog _$LlmExchangeLogFromJson(Map<String, dynamic> json) =>
    LlmExchangeLog(
      timestamp: DateTime.parse(json['timestamp'] as String),
      providerCode: json['providerCode'] as String,
      modelName: json['modelName'] as String,
      requestId: json['requestId'] as String,
      unitsCount: (json['unitsCount'] as num).toInt(),
      inputTokens: (json['inputTokens'] as num).toInt(),
      outputTokens: (json['outputTokens'] as num).toInt(),
      totalTokens: (json['totalTokens'] as num).toInt(),
      processingTimeMs: (json['processingTimeMs'] as num).toInt(),
      success: json['success'] as bool,
      errorMessage: json['errorMessage'] as String?,
      sampleTranslation: json['sampleTranslation'] as String?,
    );

Map<String, dynamic> _$LlmExchangeLogToJson(LlmExchangeLog instance) =>
    <String, dynamic>{
      'timestamp': instance.timestamp.toIso8601String(),
      'providerCode': instance.providerCode,
      'modelName': instance.modelName,
      'requestId': instance.requestId,
      'unitsCount': instance.unitsCount,
      'inputTokens': instance.inputTokens,
      'outputTokens': instance.outputTokens,
      'totalTokens': instance.totalTokens,
      'processingTimeMs': instance.processingTimeMs,
      'success': instance.success,
      'errorMessage': instance.errorMessage,
      'sampleTranslation': instance.sampleTranslation,
    };
