// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'project_language.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ProjectLanguage _$ProjectLanguageFromJson(Map<String, dynamic> json) =>
    ProjectLanguage(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      languageId: json['language_id'] as String,
      status:
          $enumDecodeNullable(_$ProjectLanguageStatusEnumMap, json['status']) ??
          ProjectLanguageStatus.pending,
      progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0.0,
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
    );

Map<String, dynamic> _$ProjectLanguageToJson(ProjectLanguage instance) =>
    <String, dynamic>{
      'id': instance.id,
      'project_id': instance.projectId,
      'language_id': instance.languageId,
      'status': _$ProjectLanguageStatusEnumMap[instance.status]!,
      'progress_percent': instance.progressPercent,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

const _$ProjectLanguageStatusEnumMap = {
  ProjectLanguageStatus.pending: 'pending',
  ProjectLanguageStatus.translating: 'translating',
  ProjectLanguageStatus.completed: 'completed',
  ProjectLanguageStatus.error: 'error',
};
