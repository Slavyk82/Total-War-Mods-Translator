// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'glossary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Glossary _$GlossaryFromJson(Map<String, dynamic> json) => Glossary(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String?,
  isGlobal: json['isGlobal'] as bool,
  projectId: json['projectId'] as String?,
  entryCount: (json['entryCount'] as num).toInt(),
  createdAt: (json['createdAt'] as num).toInt(),
  updatedAt: (json['updatedAt'] as num).toInt(),
);

Map<String, dynamic> _$GlossaryToJson(Glossary instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'description': instance.description,
  'isGlobal': instance.isGlobal,
  'projectId': instance.projectId,
  'entryCount': instance.entryCount,
  'createdAt': instance.createdAt,
  'updatedAt': instance.updatedAt,
};
