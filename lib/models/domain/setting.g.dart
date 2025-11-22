// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'setting.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Setting _$SettingFromJson(Map<String, dynamic> json) => Setting(
  id: json['id'] as String,
  key: json['key'] as String,
  value: json['value'] as String,
  valueType:
      $enumDecodeNullable(_$SettingValueTypeEnumMap, json['value_type']) ??
      SettingValueType.string,
  updatedAt: (json['updated_at'] as num).toInt(),
);

Map<String, dynamic> _$SettingToJson(Setting instance) => <String, dynamic>{
  'id': instance.id,
  'key': instance.key,
  'value': instance.value,
  'value_type': _$SettingValueTypeEnumMap[instance.valueType]!,
  'updated_at': instance.updatedAt,
};

const _$SettingValueTypeEnumMap = {
  SettingValueType.string: 'string',
  SettingValueType.integer: 'integer',
  SettingValueType.boolean: 'boolean',
  SettingValueType.json: 'json',
};
