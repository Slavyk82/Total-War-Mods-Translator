// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_version_history.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationVersionHistory _$TranslationVersionHistoryFromJson(
  Map<String, dynamic> json,
) => TranslationVersionHistory(
  id: json['id'] as String,
  versionId: json['version_id'] as String,
  translatedText: json['translated_text'] as String,
  status: $enumDecode(_$TranslationVersionStatusEnumMap, json['status']),
  confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
  changedBy: json['changed_by'] as String,
  changeReason: json['change_reason'] as String?,
  createdAt: (json['created_at'] as num).toInt(),
);

Map<String, dynamic> _$TranslationVersionHistoryToJson(
  TranslationVersionHistory instance,
) => <String, dynamic>{
  'id': instance.id,
  'version_id': instance.versionId,
  'translated_text': instance.translatedText,
  'status': _$TranslationVersionStatusEnumMap[instance.status]!,
  'confidence_score': instance.confidenceScore,
  'changed_by': instance.changedBy,
  'change_reason': instance.changeReason,
  'created_at': instance.createdAt,
};

const _$TranslationVersionStatusEnumMap = {
  TranslationVersionStatus.pending: 'pending',
  TranslationVersionStatus.translated: 'translated',
  TranslationVersionStatus.needsReview: 'needs_review',
};
