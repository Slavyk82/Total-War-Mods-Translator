// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_batch_unit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationBatchUnit _$TranslationBatchUnitFromJson(
  Map<String, dynamic> json,
) => TranslationBatchUnit(
  id: json['id'] as String,
  batchId: json['batch_id'] as String,
  unitId: json['unit_id'] as String,
  processingOrder: (json['processing_order'] as num).toInt(),
  status:
      $enumDecodeNullable(
        _$TranslationBatchUnitStatusEnumMap,
        json['status'],
      ) ??
      TranslationBatchUnitStatus.pending,
  errorMessage: json['error_message'] as String?,
  startedAt: (json['started_at'] as num?)?.toInt(),
  completedAt: (json['completed_at'] as num?)?.toInt(),
);

Map<String, dynamic> _$TranslationBatchUnitToJson(
  TranslationBatchUnit instance,
) => <String, dynamic>{
  'id': instance.id,
  'batch_id': instance.batchId,
  'unit_id': instance.unitId,
  'processing_order': instance.processingOrder,
  'status': _$TranslationBatchUnitStatusEnumMap[instance.status]!,
  'error_message': instance.errorMessage,
  'started_at': instance.startedAt,
  'completed_at': instance.completedAt,
};

const _$TranslationBatchUnitStatusEnumMap = {
  TranslationBatchUnitStatus.pending: 'pending',
  TranslationBatchUnitStatus.processing: 'processing',
  TranslationBatchUnitStatus.completed: 'completed',
  TranslationBatchUnitStatus.failed: 'failed',
};
