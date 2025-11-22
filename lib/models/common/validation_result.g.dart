// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'validation_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ValidationResult _$ValidationResultFromJson(
  Map<String, dynamic> json,
) => ValidationResult(
  isValid: json['isValid'] as bool,
  errors:
      (json['errors'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  warnings:
      (json['warnings'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$ValidationResultToJson(ValidationResult instance) =>
    <String, dynamic>{
      'isValid': instance.isValid,
      'errors': instance.errors,
      'warnings': instance.warnings,
    };

FieldValidationResult _$FieldValidationResultFromJson(
  Map<String, dynamic> json,
) => FieldValidationResult(
  fieldErrors:
      (json['fieldErrors'] as Map<String, dynamic>?)?.map(
        (k, e) =>
            MapEntry(k, (e as List<dynamic>).map((e) => e as String).toList()),
      ) ??
      const {},
  globalErrors:
      (json['globalErrors'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  warnings:
      (json['warnings'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
);

Map<String, dynamic> _$FieldValidationResultToJson(
  FieldValidationResult instance,
) => <String, dynamic>{
  'fieldErrors': instance.fieldErrors,
  'globalErrors': instance.globalErrors,
  'warnings': instance.warnings,
};
