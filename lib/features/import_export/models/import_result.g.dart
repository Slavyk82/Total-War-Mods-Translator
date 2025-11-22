// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_result.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportResult _$ImportResultFromJson(Map<String, dynamic> json) => ImportResult(
  totalProcessed: (json['total_processed'] as num).toInt(),
  successCount: (json['success_count'] as num).toInt(),
  skippedCount: (json['skipped_count'] as num).toInt(),
  errorCount: (json['error_count'] as num).toInt(),
  errors:
      (json['errors'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, e as String),
      ) ??
      const {},
  importedIds:
      (json['imported_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  durationMs: (json['duration_ms'] as num).toInt(),
);

Map<String, dynamic> _$ImportResultToJson(ImportResult instance) =>
    <String, dynamic>{
      'total_processed': instance.totalProcessed,
      'success_count': instance.successCount,
      'skipped_count': instance.skippedCount,
      'error_count': instance.errorCount,
      'errors': instance.errors,
      'imported_ids': instance.importedIds,
      'duration_ms': instance.durationMs,
    };

ImportValidationResult _$ImportValidationResultFromJson(
  Map<String, dynamic> json,
) => ImportValidationResult(
  isValid: json['is_valid'] as bool,
  errors:
      (json['errors'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  warnings:
      (json['warnings'] as List<dynamic>?)?.map((e) => e as String).toList() ??
      const [],
  duplicateKeys:
      (json['duplicate_keys'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
  missingColumns:
      (json['missing_columns'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList() ??
      const [],
);

Map<String, dynamic> _$ImportValidationResultToJson(
  ImportValidationResult instance,
) => <String, dynamic>{
  'is_valid': instance.isValid,
  'errors': instance.errors,
  'warnings': instance.warnings,
  'duplicate_keys': instance.duplicateKeys,
  'missing_columns': instance.missingColumns,
};
