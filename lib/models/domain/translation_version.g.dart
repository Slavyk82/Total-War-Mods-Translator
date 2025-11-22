// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_version.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationVersion _$TranslationVersionFromJson(Map<String, dynamic> json) =>
    TranslationVersion(
      id: json['id'] as String,
      unitId: json['unit_id'] as String,
      projectLanguageId: json['project_language_id'] as String,
      translatedText: json['translated_text'] as String?,
      isManuallyEdited: json['is_manually_edited'] == null
          ? false
          : const BoolIntConverter().fromJson(json['is_manually_edited']),
      status:
          $enumDecodeNullable(
            _$TranslationVersionStatusEnumMap,
            json['status'],
          ) ??
          TranslationVersionStatus.pending,
      confidenceScore: (json['confidence_score'] as num?)?.toDouble(),
      validationIssues: json['validation_issues'] as String?,
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
    );

Map<String, dynamic> _$TranslationVersionToJson(TranslationVersion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'unit_id': instance.unitId,
      'project_language_id': instance.projectLanguageId,
      'translated_text': instance.translatedText,
      'is_manually_edited': const BoolIntConverter().toJson(
        instance.isManuallyEdited,
      ),
      'status': _$TranslationVersionStatusEnumMap[instance.status]!,
      'confidence_score': instance.confidenceScore,
      'validation_issues': instance.validationIssues,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

const _$TranslationVersionStatusEnumMap = {
  TranslationVersionStatus.pending: 'pending',
  TranslationVersionStatus.translating: 'translating',
  TranslationVersionStatus.translated: 'translated',
  TranslationVersionStatus.reviewed: 'reviewed',
  TranslationVersionStatus.approved: 'approved',
  TranslationVersionStatus.needsReview: 'needs_review',
};
