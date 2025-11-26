// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_progress.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationProgress _$TranslationProgressFromJson(Map<String, dynamic> json) =>
    TranslationProgress(
      batchId: json['batchId'] as String,
      status: $enumDecode(_$TranslationProgressStatusEnumMap, json['status']),
      totalUnits: (json['totalUnits'] as num).toInt(),
      processedUnits: (json['processedUnits'] as num).toInt(),
      successfulUnits: (json['successfulUnits'] as num).toInt(),
      failedUnits: (json['failedUnits'] as num).toInt(),
      skippedUnits: (json['skippedUnits'] as num).toInt(),
      currentPhase: $enumDecode(
        _$TranslationPhaseEnumMap,
        json['currentPhase'],
      ),
      phaseDetail: json['phaseDetail'] as String?,
      estimatedSecondsRemaining: (json['estimatedSecondsRemaining'] as num?)
          ?.toInt(),
      tokensUsed: (json['tokensUsed'] as num).toInt(),
      tmReuseRate: (json['tmReuseRate'] as num).toDouble(),
      errorMessage: json['errorMessage'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      timestamp: DateTime.parse(json['timestamp'] as String),
      llmLogs:
          (json['llmLogs'] as List<dynamic>?)
              ?.map((e) => LlmExchangeLog.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );

Map<String, dynamic> _$TranslationProgressToJson(
  TranslationProgress instance,
) => <String, dynamic>{
  'batchId': instance.batchId,
  'status': _$TranslationProgressStatusEnumMap[instance.status]!,
  'totalUnits': instance.totalUnits,
  'processedUnits': instance.processedUnits,
  'successfulUnits': instance.successfulUnits,
  'failedUnits': instance.failedUnits,
  'skippedUnits': instance.skippedUnits,
  'currentPhase': _$TranslationPhaseEnumMap[instance.currentPhase]!,
  'phaseDetail': instance.phaseDetail,
  'estimatedSecondsRemaining': instance.estimatedSecondsRemaining,
  'tokensUsed': instance.tokensUsed,
  'tmReuseRate': instance.tmReuseRate,
  'errorMessage': instance.errorMessage,
  'metadata': instance.metadata,
  'timestamp': instance.timestamp.toIso8601String(),
  'llmLogs': instance.llmLogs,
};

const _$TranslationProgressStatusEnumMap = {
  TranslationProgressStatus.queued: 'queued',
  TranslationProgressStatus.inProgress: 'in_progress',
  TranslationProgressStatus.paused: 'paused',
  TranslationProgressStatus.completed: 'completed',
  TranslationProgressStatus.failed: 'failed',
  TranslationProgressStatus.cancelled: 'cancelled',
};

const _$TranslationPhaseEnumMap = {
  TranslationPhase.initializing: 'initializing',
  TranslationPhase.tmExactLookup: 'tm_exact_lookup',
  TranslationPhase.tmFuzzyLookup: 'tm_fuzzy_lookup',
  TranslationPhase.buildingPrompt: 'building_prompt',
  TranslationPhase.llmTranslation: 'llm_translation',
  TranslationPhase.validating: 'validating',
  TranslationPhase.saving: 'saving',
  TranslationPhase.updatingTm: 'updating_tm',
  TranslationPhase.finalizing: 'finalizing',
  TranslationPhase.completed: 'completed',
};
