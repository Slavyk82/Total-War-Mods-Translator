// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_version_change.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModVersionChange _$ModVersionChangeFromJson(Map<String, dynamic> json) =>
    ModVersionChange(
      id: json['id'] as String,
      versionId: json['version_id'] as String,
      unitKey: json['unit_key'] as String,
      changeType: $enumDecode(
        _$ModVersionChangeTypeEnumMap,
        json['change_type'],
      ),
      oldSourceText: json['old_source_text'] as String?,
      newSourceText: json['new_source_text'] as String?,
      detectedAt: (json['detected_at'] as num).toInt(),
    );

Map<String, dynamic> _$ModVersionChangeToJson(ModVersionChange instance) =>
    <String, dynamic>{
      'id': instance.id,
      'version_id': instance.versionId,
      'unit_key': instance.unitKey,
      'change_type': _$ModVersionChangeTypeEnumMap[instance.changeType]!,
      'old_source_text': instance.oldSourceText,
      'new_source_text': instance.newSourceText,
      'detected_at': instance.detectedAt,
    };

const _$ModVersionChangeTypeEnumMap = {
  ModVersionChangeType.added: 'added',
  ModVersionChangeType.modified: 'modified',
  ModVersionChangeType.deleted: 'deleted',
};
