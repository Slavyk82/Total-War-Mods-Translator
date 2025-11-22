import 'package:json_annotation/json_annotation.dart';

part 'import_result.g.dart';

/// Result of an import operation
@JsonSerializable()
class ImportResult {
  /// Total number of rows processed
  @JsonKey(name: 'total_processed')
  final int totalProcessed;

  /// Number of successful imports
  @JsonKey(name: 'success_count')
  final int successCount;

  /// Number of skipped rows (conflicts/duplicates)
  @JsonKey(name: 'skipped_count')
  final int skippedCount;

  /// Number of errors
  @JsonKey(name: 'error_count')
  final int errorCount;

  /// Detailed error messages (key -> error message)
  final Map<String, String> errors;

  /// IDs of imported translation versions
  @JsonKey(name: 'imported_ids')
  final List<String> importedIds;

  /// Duration of import operation in milliseconds
  @JsonKey(name: 'duration_ms')
  final int durationMs;

  const ImportResult({
    required this.totalProcessed,
    required this.successCount,
    required this.skippedCount,
    required this.errorCount,
    this.errors = const {},
    this.importedIds = const [],
    required this.durationMs,
  });

  /// Whether the import was successful (no errors)
  bool get isSuccess => errorCount == 0;

  /// Whether the import was partially successful
  bool get isPartialSuccess => successCount > 0 && errorCount > 0;

  /// Whether the import completely failed
  bool get isFailed => successCount == 0 && errorCount > 0;

  /// Duration in human-readable format
  String get durationFormatted {
    if (durationMs < 1000) return '${durationMs}ms';
    final seconds = durationMs / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds / 60;
    return '${minutes.toStringAsFixed(1)}m';
  }

  ImportResult copyWith({
    int? totalProcessed,
    int? successCount,
    int? skippedCount,
    int? errorCount,
    Map<String, String>? errors,
    List<String>? importedIds,
    int? durationMs,
  }) {
    return ImportResult(
      totalProcessed: totalProcessed ?? this.totalProcessed,
      successCount: successCount ?? this.successCount,
      skippedCount: skippedCount ?? this.skippedCount,
      errorCount: errorCount ?? this.errorCount,
      errors: errors ?? this.errors,
      importedIds: importedIds ?? this.importedIds,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  factory ImportResult.fromJson(Map<String, dynamic> json) =>
      _$ImportResultFromJson(json);

  Map<String, dynamic> toJson() => _$ImportResultToJson(this);
}

/// Validation result for import data
@JsonSerializable()
class ImportValidationResult {
  /// Whether validation passed
  @JsonKey(name: 'is_valid')
  final bool isValid;

  /// Validation errors
  final List<String> errors;

  /// Validation warnings
  final List<String> warnings;

  /// Duplicate keys found
  @JsonKey(name: 'duplicate_keys')
  final List<String> duplicateKeys;

  /// Missing required columns
  @JsonKey(name: 'missing_columns')
  final List<String> missingColumns;

  const ImportValidationResult({
    required this.isValid,
    this.errors = const [],
    this.warnings = const [],
    this.duplicateKeys = const [],
    this.missingColumns = const [],
  });

  /// Whether there are any issues (errors or warnings)
  bool get hasIssues => errors.isNotEmpty || warnings.isNotEmpty;

  ImportValidationResult copyWith({
    bool? isValid,
    List<String>? errors,
    List<String>? warnings,
    List<String>? duplicateKeys,
    List<String>? missingColumns,
  }) {
    return ImportValidationResult(
      isValid: isValid ?? this.isValid,
      errors: errors ?? this.errors,
      warnings: warnings ?? this.warnings,
      duplicateKeys: duplicateKeys ?? this.duplicateKeys,
      missingColumns: missingColumns ?? this.missingColumns,
    );
  }

  factory ImportValidationResult.fromJson(Map<String, dynamic> json) =>
      _$ImportValidationResultFromJson(json);

  Map<String, dynamic> toJson() => _$ImportValidationResultToJson(this);
}
