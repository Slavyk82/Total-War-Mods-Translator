// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_batch.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationBatch _$TranslationBatchFromJson(Map<String, dynamic> json) =>
    TranslationBatch(
      id: json['id'] as String,
      projectLanguageId: json['project_language_id'] as String,
      status:
          $enumDecodeNullable(
            _$TranslationBatchStatusEnumMap,
            json['status'],
          ) ??
          TranslationBatchStatus.pending,
      providerId: json['provider_id'] as String,
      batchNumber: (json['batch_number'] as num).toInt(),
      unitsCount: (json['units_count'] as num?)?.toInt() ?? 0,
      unitsCompleted: (json['units_completed'] as num?)?.toInt() ?? 0,
      startedAt: (json['started_at'] as num?)?.toInt(),
      completedAt: (json['completed_at'] as num?)?.toInt(),
      errorMessage: json['error_message'] as String?,
      retryCount: (json['retry_count'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$TranslationBatchToJson(TranslationBatch instance) =>
    <String, dynamic>{
      'id': instance.id,
      'project_language_id': instance.projectLanguageId,
      'status': _$TranslationBatchStatusEnumMap[instance.status]!,
      'provider_id': instance.providerId,
      'batch_number': instance.batchNumber,
      'units_count': instance.unitsCount,
      'units_completed': instance.unitsCompleted,
      'started_at': instance.startedAt,
      'completed_at': instance.completedAt,
      'error_message': instance.errorMessage,
      'retry_count': instance.retryCount,
    };

const _$TranslationBatchStatusEnumMap = {
  TranslationBatchStatus.pending: 'pending',
  TranslationBatchStatus.processing: 'processing',
  TranslationBatchStatus.completed: 'completed',
  TranslationBatchStatus.failed: 'failed',
  TranslationBatchStatus.cancelled: 'cancelled',
};
