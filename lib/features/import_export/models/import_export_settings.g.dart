// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'import_export_settings.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ImportSettings _$ImportSettingsFromJson(Map<String, dynamic> json) =>
    ImportSettings(
      format: $enumDecode(_$ImportFormatEnumMap, json['format']),
      projectId: json['project_id'] as String,
      targetLanguageId: json['target_language_id'] as String,
      encoding: json['encoding'] as String? ?? 'utf-8',
      hasHeaderRow: json['has_header_row'] as bool? ?? true,
      columnMapping:
          (json['column_mapping'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, $enumDecode(_$ImportColumnEnumMap, e)),
          ) ??
          const {},
      conflictStrategy:
          $enumDecodeNullable(
            _$ConflictResolutionStrategyEnumMap,
            json['conflict_strategy'],
          ) ??
          ConflictResolutionStrategy.skipExisting,
      validationOptions: json['validation_options'] == null
          ? const ImportValidationOptions()
          : ImportValidationOptions.fromJson(
              json['validation_options'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$ImportSettingsToJson(ImportSettings instance) =>
    <String, dynamic>{
      'format': _$ImportFormatEnumMap[instance.format]!,
      'project_id': instance.projectId,
      'target_language_id': instance.targetLanguageId,
      'encoding': instance.encoding,
      'has_header_row': instance.hasHeaderRow,
      'column_mapping': instance.columnMapping.map(
        (k, e) => MapEntry(k, _$ImportColumnEnumMap[e]!),
      ),
      'conflict_strategy':
          _$ConflictResolutionStrategyEnumMap[instance.conflictStrategy]!,
      'validation_options': instance.validationOptions,
    };

const _$ImportFormatEnumMap = {
  ImportFormat.csv: 'csv',
  ImportFormat.json: 'json',
  ImportFormat.excel: 'excel',
  ImportFormat.loc: 'loc',
};

const _$ImportColumnEnumMap = {
  ImportColumn.key: 'key',
  ImportColumn.sourceText: 'source_text',
  ImportColumn.targetText: 'target_text',
  ImportColumn.status: 'status',
  ImportColumn.notes: 'notes',
  ImportColumn.context: 'context',
  ImportColumn.skip: 'skip',
};

const _$ConflictResolutionStrategyEnumMap = {
  ConflictResolutionStrategy.skipExisting: 'skip_existing',
  ConflictResolutionStrategy.overwrite: 'overwrite',
  ConflictResolutionStrategy.keepNewer: 'keep_newer',
  ConflictResolutionStrategy.merge: 'merge',
  ConflictResolutionStrategy.askMe: 'ask_me',
};

ImportValidationOptions _$ImportValidationOptionsFromJson(
  Map<String, dynamic> json,
) => ImportValidationOptions(
  checkDuplicates: json['check_duplicates'] as bool? ?? true,
  validateColumns: json['validate_columns'] as bool? ?? true,
  warnSourceMismatch: json['warn_source_mismatch'] as bool? ?? true,
  validateLanguage: json['validate_language'] as bool? ?? true,
);

Map<String, dynamic> _$ImportValidationOptionsToJson(
  ImportValidationOptions instance,
) => <String, dynamic>{
  'check_duplicates': instance.checkDuplicates,
  'validate_columns': instance.validateColumns,
  'warn_source_mismatch': instance.warnSourceMismatch,
  'validate_language': instance.validateLanguage,
};

ExportSettings _$ExportSettingsFromJson(Map<String, dynamic> json) =>
    ExportSettings(
      format: $enumDecode(_$ExportFormatEnumMap, json['format']),
      projectId: json['project_id'] as String,
      targetLanguageId: json['target_language_id'] as String,
      columns:
          (json['columns'] as List<dynamic>?)
              ?.map((e) => $enumDecode(_$ExportColumnEnumMap, e))
              .toList() ??
          const [
            ExportColumn.key,
            ExportColumn.sourceText,
            ExportColumn.targetText,
            ExportColumn.status,
          ],
      filterOptions: json['filter_options'] == null
          ? const ExportFilterOptions()
          : ExportFilterOptions.fromJson(
              json['filter_options'] as Map<String, dynamic>,
            ),
      formatOptions: json['format_options'] == null
          ? const ExportFormatOptions()
          : ExportFormatOptions.fromJson(
              json['format_options'] as Map<String, dynamic>,
            ),
    );

Map<String, dynamic> _$ExportSettingsToJson(
  ExportSettings instance,
) => <String, dynamic>{
  'format': _$ExportFormatEnumMap[instance.format]!,
  'project_id': instance.projectId,
  'target_language_id': instance.targetLanguageId,
  'columns': instance.columns.map((e) => _$ExportColumnEnumMap[e]!).toList(),
  'filter_options': instance.filterOptions,
  'format_options': instance.formatOptions,
};

const _$ExportFormatEnumMap = {
  ExportFormat.csv: 'csv',
  ExportFormat.json: 'json',
  ExportFormat.excel: 'excel',
  ExportFormat.loc: 'loc',
};

const _$ExportColumnEnumMap = {
  ExportColumn.key: 'key',
  ExportColumn.sourceText: 'source_text',
  ExportColumn.targetText: 'target_text',
  ExportColumn.status: 'status',
  ExportColumn.notes: 'notes',
  ExportColumn.context: 'context',
  ExportColumn.qualityScore: 'quality_score',
  ExportColumn.createdAt: 'created_at',
  ExportColumn.updatedAt: 'updated_at',
  ExportColumn.changedBy: 'changed_by',
};

ExportFilterOptions _$ExportFilterOptionsFromJson(Map<String, dynamic> json) =>
    ExportFilterOptions(
      statusFilter: (json['status_filter'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      contextFilter: json['context_filter'] as String?,
      translationsOnly: json['translations_only'] as bool? ?? false,
      validatedOnly: json['validated_only'] as bool? ?? false,
      createdAfter: (json['created_after'] as num?)?.toInt(),
      updatedAfter: (json['updated_after'] as num?)?.toInt(),
    );

Map<String, dynamic> _$ExportFilterOptionsToJson(
  ExportFilterOptions instance,
) => <String, dynamic>{
  'status_filter': instance.statusFilter,
  'context_filter': instance.contextFilter,
  'translations_only': instance.translationsOnly,
  'validated_only': instance.validatedOnly,
  'created_after': instance.createdAfter,
  'updated_after': instance.updatedAfter,
};

ExportFormatOptions _$ExportFormatOptionsFromJson(Map<String, dynamic> json) =>
    ExportFormatOptions(
      includeHeader: json['include_header'] as bool? ?? true,
      prettyPrint: json['pretty_print'] as bool? ?? true,
      encoding: json['encoding'] as String? ?? 'utf-8',
      locPrefix: json['loc_prefix'] as String?,
    );

Map<String, dynamic> _$ExportFormatOptionsToJson(
  ExportFormatOptions instance,
) => <String, dynamic>{
  'include_header': instance.includeHeader,
  'pretty_print': instance.prettyPrint,
  'encoding': instance.encoding,
  'loc_prefix': instance.locPrefix,
};
