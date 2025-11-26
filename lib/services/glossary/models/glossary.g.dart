// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glossary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Glossary _$GlossaryFromJson(Map<String, dynamic> json) => Glossary(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  isGlobal: const BoolIntConverter().fromJson(json['is_global']),
  gameInstallationId: json['game_installation_id'] as String?,
  targetLanguageId: json['target_language_id'] as String?,
  entryCount: (json['entryCount'] as num?)?.toInt() ?? 0,
  createdAt: (json['created_at'] as num).toInt(),
  updatedAt: (json['updated_at'] as num).toInt(),
);

Map<String, dynamic> _$GlossaryToJson(Glossary instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'is_global': const BoolIntConverter().toJson(instance.isGlobal),
  'game_installation_id': instance.gameInstallationId,
  'target_language_id': instance.targetLanguageId,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
};
