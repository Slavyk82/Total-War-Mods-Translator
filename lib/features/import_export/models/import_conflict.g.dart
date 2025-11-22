// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_conflict.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportConflict _$ImportConflictFromJson(Map<String, dynamic> json) =>
    ImportConflict(
      key: json['key'] as String,
      existingData: ConflictTranslation.fromJson(
        json['existing_data'] as Map<String, dynamic>,
      ),
      importedData: ConflictTranslation.fromJson(
        json['imported_data'] as Map<String, dynamic>,
      ),
      sourceTextDiffers: json['source_text_differs'] as bool? ?? false,
      resolution: $enumDecodeNullable(
        _$ConflictResolutionEnumMap,
        json['resolution'],
      ),
    );

Map<String, dynamic> _$ImportConflictToJson(ImportConflict instance) =>
    <String, dynamic>{
      'key': instance.key,
      'existing_data': instance.existingData,
      'imported_data': instance.importedData,
      'source_text_differs': instance.sourceTextDiffers,
      'resolution': _$ConflictResolutionEnumMap[instance.resolution],
    };

const _$ConflictResolutionEnumMap = {
  ConflictResolution.keepExisting: 'keep_existing',
  ConflictResolution.useImported: 'use_imported',
  ConflictResolution.merge: 'merge',
};

ConflictTranslation _$ConflictTranslationFromJson(Map<String, dynamic> json) =>
    ConflictTranslation(
      sourceText: json['source_text'] as String?,
      translatedText: json['translated_text'] as String?,
      status: json['status'] as String?,
      updatedAt: (json['updated_at'] as num?)?.toInt(),
      changedBy: json['changed_by'] as String?,
      notes: json['notes'] as String?,
    );

Map<String, dynamic> _$ConflictTranslationToJson(
  ConflictTranslation instance,
) => <String, dynamic>{
  'source_text': instance.sourceText,
  'translated_text': instance.translatedText,
  'status': instance.status,
  'updated_at': instance.updatedAt,
  'changed_by': instance.changedBy,
  'notes': instance.notes,
};

ConflictResolutions _$ConflictResolutionsFromJson(Map<String, dynamic> json) =>
    ConflictResolutions(
      resolutions:
          (json['resolutions'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, $enumDecode(_$ConflictResolutionEnumMap, e)),
          ) ??
          const {},
      defaultResolution: $enumDecodeNullable(
        _$ConflictResolutionEnumMap,
        json['default_resolution'],
      ),
    );

Map<String, dynamic> _$ConflictResolutionsToJson(
  ConflictResolutions instance,
) => <String, dynamic>{
  'resolutions': instance.resolutions.map(
    (k, e) => MapEntry(k, _$ConflictResolutionEnumMap[e]!),
  ),
  'default_resolution': _$ConflictResolutionEnumMap[instance.defaultResolution],
};
