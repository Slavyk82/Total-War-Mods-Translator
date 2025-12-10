import 'package:json_annotation/json_annotation.dart';

part 'import_export_settings.g.dart';

/// Format for importing translation data
enum ImportFormat {
  @JsonValue('csv')
  csv,
  @JsonValue('json')
  json,
  @JsonValue('excel')
  excel,
  @JsonValue('loc')
  loc,
}

/// Column type for import mapping
enum ImportColumn {
  @JsonValue('key')
  key,
  @JsonValue('source_text')
  sourceText,
  @JsonValue('target_text')
  targetText,
  @JsonValue('status')
  status,
  @JsonValue('notes')
  notes,
  @JsonValue('context')
  context,
  @JsonValue('skip')
  skip,
}

/// Strategy for resolving conflicts during import
enum ConflictResolutionStrategy {
  @JsonValue('skip_existing')
  skipExisting,
  @JsonValue('overwrite')
  overwrite,
  @JsonValue('keep_newer')
  keepNewer,
  @JsonValue('merge')
  merge,
  @JsonValue('ask_me')
  askMe,
}

/// Format for exporting translation data
enum ExportFormat {
  @JsonValue('csv')
  csv,
  @JsonValue('json')
  json,
  @JsonValue('excel')
  excel,
  @JsonValue('loc')
  loc,
}

/// Column type for export
enum ExportColumn {
  @JsonValue('key')
  key,
  @JsonValue('source_text')
  sourceText,
  @JsonValue('target_text')
  targetText,
  @JsonValue('status')
  status,
  @JsonValue('notes')
  notes,
  @JsonValue('context')
  context,
  @JsonValue('created_at')
  createdAt,
  @JsonValue('updated_at')
  updatedAt,
  @JsonValue('changed_by')
  changedBy,
}

/// Settings for importing translation data
@JsonSerializable()
class ImportSettings {
  /// Import format
  final ImportFormat format;

  /// Target project ID
  @JsonKey(name: 'project_id')
  final String projectId;

  /// Target language ID
  @JsonKey(name: 'target_language_id')
  final String targetLanguageId;

  /// File encoding (e.g., 'utf-8', 'utf-16')
  final String encoding;

  /// Whether the file has a header row
  @JsonKey(name: 'has_header_row')
  final bool hasHeaderRow;

  /// Column mapping (file column name -> import column type)
  @JsonKey(name: 'column_mapping')
  final Map<String, ImportColumn> columnMapping;

  /// Conflict resolution strategy
  @JsonKey(name: 'conflict_strategy')
  final ConflictResolutionStrategy conflictStrategy;

  /// Validation options
  @JsonKey(name: 'validation_options')
  final ImportValidationOptions validationOptions;

  const ImportSettings({
    required this.format,
    required this.projectId,
    required this.targetLanguageId,
    this.encoding = 'utf-8',
    this.hasHeaderRow = true,
    this.columnMapping = const {},
    this.conflictStrategy = ConflictResolutionStrategy.skipExisting,
    this.validationOptions = const ImportValidationOptions(),
  });

  ImportSettings copyWith({
    ImportFormat? format,
    String? projectId,
    String? targetLanguageId,
    String? encoding,
    bool? hasHeaderRow,
    Map<String, ImportColumn>? columnMapping,
    ConflictResolutionStrategy? conflictStrategy,
    ImportValidationOptions? validationOptions,
  }) {
    return ImportSettings(
      format: format ?? this.format,
      projectId: projectId ?? this.projectId,
      targetLanguageId: targetLanguageId ?? this.targetLanguageId,
      encoding: encoding ?? this.encoding,
      hasHeaderRow: hasHeaderRow ?? this.hasHeaderRow,
      columnMapping: columnMapping ?? this.columnMapping,
      conflictStrategy: conflictStrategy ?? this.conflictStrategy,
      validationOptions: validationOptions ?? this.validationOptions,
    );
  }

  factory ImportSettings.fromJson(Map<String, dynamic> json) =>
      _$ImportSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$ImportSettingsToJson(this);
}

/// Validation options for import
@JsonSerializable()
class ImportValidationOptions {
  /// Check for duplicate keys in import file
  @JsonKey(name: 'check_duplicates')
  final bool checkDuplicates;

  /// Validate required columns are present
  @JsonKey(name: 'validate_columns')
  final bool validateColumns;

  /// Warn if source text differs from existing
  @JsonKey(name: 'warn_source_mismatch')
  final bool warnSourceMismatch;

  /// Validate target language exists
  @JsonKey(name: 'validate_language')
  final bool validateLanguage;

  const ImportValidationOptions({
    this.checkDuplicates = true,
    this.validateColumns = true,
    this.warnSourceMismatch = true,
    this.validateLanguage = true,
  });

  ImportValidationOptions copyWith({
    bool? checkDuplicates,
    bool? validateColumns,
    bool? warnSourceMismatch,
    bool? validateLanguage,
  }) {
    return ImportValidationOptions(
      checkDuplicates: checkDuplicates ?? this.checkDuplicates,
      validateColumns: validateColumns ?? this.validateColumns,
      warnSourceMismatch: warnSourceMismatch ?? this.warnSourceMismatch,
      validateLanguage: validateLanguage ?? this.validateLanguage,
    );
  }

  factory ImportValidationOptions.fromJson(Map<String, dynamic> json) =>
      _$ImportValidationOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$ImportValidationOptionsToJson(this);
}

/// Settings for exporting translation data
@JsonSerializable()
class ExportSettings {
  /// Export format
  final ExportFormat format;

  /// Source project ID
  @JsonKey(name: 'project_id')
  final String projectId;

  /// Target language ID
  @JsonKey(name: 'target_language_id')
  final String targetLanguageId;

  /// Columns to include in export
  final List<ExportColumn> columns;

  /// Filter options
  @JsonKey(name: 'filter_options')
  final ExportFilterOptions filterOptions;

  /// Format-specific options
  @JsonKey(name: 'format_options')
  final ExportFormatOptions formatOptions;

  const ExportSettings({
    required this.format,
    required this.projectId,
    required this.targetLanguageId,
    this.columns = const [
      ExportColumn.key,
      ExportColumn.sourceText,
      ExportColumn.targetText,
      ExportColumn.status,
    ],
    this.filterOptions = const ExportFilterOptions(),
    this.formatOptions = const ExportFormatOptions(),
  });

  ExportSettings copyWith({
    ExportFormat? format,
    String? projectId,
    String? targetLanguageId,
    List<ExportColumn>? columns,
    ExportFilterOptions? filterOptions,
    ExportFormatOptions? formatOptions,
  }) {
    return ExportSettings(
      format: format ?? this.format,
      projectId: projectId ?? this.projectId,
      targetLanguageId: targetLanguageId ?? this.targetLanguageId,
      columns: columns ?? this.columns,
      filterOptions: filterOptions ?? this.filterOptions,
      formatOptions: formatOptions ?? this.formatOptions,
    );
  }

  factory ExportSettings.fromJson(Map<String, dynamic> json) =>
      _$ExportSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$ExportSettingsToJson(this);
}

/// Filter options for export
@JsonSerializable()
class ExportFilterOptions {
  /// Include only specific statuses (null = all)
  @JsonKey(name: 'status_filter')
  final List<String>? statusFilter;

  /// Filter by file/context
  @JsonKey(name: 'context_filter')
  final String? contextFilter;

  /// Export only translated items
  @JsonKey(name: 'translations_only')
  final bool translationsOnly;

  /// Export only validated items
  @JsonKey(name: 'validated_only')
  final bool validatedOnly;

  /// Created after timestamp
  @JsonKey(name: 'created_after')
  final int? createdAfter;

  /// Updated after timestamp
  @JsonKey(name: 'updated_after')
  final int? updatedAfter;

  const ExportFilterOptions({
    this.statusFilter,
    this.contextFilter,
    this.translationsOnly = false,
    this.validatedOnly = false,
    this.createdAfter,
    this.updatedAfter,
  });

  ExportFilterOptions copyWith({
    List<String>? statusFilter,
    String? contextFilter,
    bool? translationsOnly,
    bool? validatedOnly,
    int? createdAfter,
    int? updatedAfter,
  }) {
    return ExportFilterOptions(
      statusFilter: statusFilter ?? this.statusFilter,
      contextFilter: contextFilter ?? this.contextFilter,
      translationsOnly: translationsOnly ?? this.translationsOnly,
      validatedOnly: validatedOnly ?? this.validatedOnly,
      createdAfter: createdAfter ?? this.createdAfter,
      updatedAfter: updatedAfter ?? this.updatedAfter,
    );
  }

  factory ExportFilterOptions.fromJson(Map<String, dynamic> json) =>
      _$ExportFilterOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$ExportFilterOptionsToJson(this);
}

/// Format-specific export options
@JsonSerializable()
class ExportFormatOptions {
  /// Include header row (CSV/Excel)
  @JsonKey(name: 'include_header')
  final bool includeHeader;

  /// Pretty print JSON
  @JsonKey(name: 'pretty_print')
  final bool prettyPrint;

  /// Output encoding (CSV)
  final String encoding;

  /// Prefix for .loc format
  @JsonKey(name: 'loc_prefix')
  final String? locPrefix;

  const ExportFormatOptions({
    this.includeHeader = true,
    this.prettyPrint = true,
    this.encoding = 'utf-8',
    this.locPrefix,
  });

  ExportFormatOptions copyWith({
    bool? includeHeader,
    bool? prettyPrint,
    String? encoding,
    String? locPrefix,
  }) {
    return ExportFormatOptions(
      includeHeader: includeHeader ?? this.includeHeader,
      prettyPrint: prettyPrint ?? this.prettyPrint,
      encoding: encoding ?? this.encoding,
      locPrefix: locPrefix ?? this.locPrefix,
    );
  }

  factory ExportFormatOptions.fromJson(Map<String, dynamic> json) =>
      _$ExportFormatOptionsFromJson(json);

  Map<String, dynamic> toJson() => _$ExportFormatOptionsToJson(this);
}
