// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'llm_model_info.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LlmModelInfo _$LlmModelInfoFromJson(Map<String, dynamic> json) => LlmModelInfo(
  id: json['id'] as String,
  displayName: json['displayName'] as String?,
  createdAt: json['createdAt'] == null
      ? null
      : DateTime.parse(json['createdAt'] as String),
  type: json['type'] as String?,
  ownedBy: json['ownedBy'] as String?,
);

Map<String, dynamic> _$LlmModelInfoToJson(LlmModelInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'createdAt': instance.createdAt?.toIso8601String(),
      'type': instance.type,
      'ownedBy': instance.ownedBy,
    };
