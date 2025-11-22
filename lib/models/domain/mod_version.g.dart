// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mod_version.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ModVersion _$ModVersionFromJson(Map<String, dynamic> json) => ModVersion(
  id: json['id'] as String,
  projectId: json['project_id'] as String,
  versionString: json['version_string'] as String,
  releaseDate: (json['release_date'] as num?)?.toInt(),
  steamUpdateTimestamp: (json['steam_update_timestamp'] as num?)?.toInt(),
  unitsAdded: (json['units_added'] as num?)?.toInt() ?? 0,
  unitsModified: (json['units_modified'] as num?)?.toInt() ?? 0,
  unitsDeleted: (json['units_deleted'] as num?)?.toInt() ?? 0,
  isCurrent: json['is_current'] == null
      ? true
      : const BoolIntConverter().fromJson(json['is_current']),
  detectedAt: (json['detected_at'] as num).toInt(),
);

Map<String, dynamic> _$ModVersionToJson(ModVersion instance) =>
    <String, dynamic>{
      'id': instance.id,
      'project_id': instance.projectId,
      'version_string': instance.versionString,
      'release_date': instance.releaseDate,
      'steam_update_timestamp': instance.steamUpdateTimestamp,
      'units_added': instance.unitsAdded,
      'units_modified': instance.unitsModified,
      'units_deleted': instance.unitsDeleted,
      'is_current': const BoolIntConverter().toJson(instance.isCurrent),
      'detected_at': instance.detectedAt,
    };
