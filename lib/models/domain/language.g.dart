// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'language.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Language _$LanguageFromJson(Map<String, dynamic> json) => Language(
  id: json['id'] as String,
  code: json['code'] as String,
  name: json['name'] as String,
  nativeName: json['native_name'] as String,
  isActive: json['is_active'] == null
      ? true
      : const BoolIntConverter().fromJson(json['is_active']),
);

Map<String, dynamic> _$LanguageToJson(Language instance) => <String, dynamic>{
  'id': instance.id,
  'code': instance.code,
  'name': instance.name,
  'native_name': instance.nativeName,
  'is_active': const BoolIntConverter().toJson(instance.isActive),
};
