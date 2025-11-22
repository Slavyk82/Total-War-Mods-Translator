// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'localization_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalizationEntry _$LocalizationEntryFromJson(Map<String, dynamic> json) =>
    LocalizationEntry(
      key: json['key'] as String,
      value: json['value'] as String,
      lineNumber: (json['lineNumber'] as num?)?.toInt(),
      rawValue: json['rawValue'] as String?,
      isModified: json['isModified'] as bool? ?? false,
    );

Map<String, dynamic> _$LocalizationEntryToJson(LocalizationEntry instance) =>
    <String, dynamic>{
      'key': instance.key,
      'value': instance.value,
      'lineNumber': instance.lineNumber,
      'rawValue': instance.rawValue,
      'isModified': instance.isModified,
    };
