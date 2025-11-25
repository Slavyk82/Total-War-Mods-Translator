// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'translation_unit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TranslationUnit _$TranslationUnitFromJson(Map<String, dynamic> json) =>
    TranslationUnit(
      id: json['id'] as String,
      projectId: json['project_id'] as String,
      key: json['key'] as String,
      sourceText: json['source_text'] as String,
      context: json['context'] as String?,
      notes: json['notes'] as String?,
      sourceLocFile: json['source_loc_file'] as String?,
      isObsolete: json['is_obsolete'] == null
          ? false
          : const BoolIntConverter().fromJson(json['is_obsolete']),
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
    );

Map<String, dynamic> _$TranslationUnitToJson(TranslationUnit instance) =>
    <String, dynamic>{
      'id': instance.id,
      'project_id': instance.projectId,
      'key': instance.key,
      'source_text': instance.sourceText,
      'context': instance.context,
      'notes': instance.notes,
      'source_loc_file': instance.sourceLocFile,
      'is_obsolete': const BoolIntConverter().toJson(instance.isObsolete),
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };
