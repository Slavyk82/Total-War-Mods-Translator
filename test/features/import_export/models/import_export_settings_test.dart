import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';

/// Unit tests for the import/export settings models and enums
/// (json_serializable). Covers every enum's JSON value mapping, constructor
/// defaults, `copyWith` field overrides and nested JSON round-trips. None of
/// these classes override `==`, so JSON assertions compare field-by-field.
void main() {
  group('enum JSON values', () {
    test('ImportFormat maps each value', () {
      expect(ImportFormat.values, hasLength(4));
      const settings = ImportSettings(
        format: ImportFormat.excel,
        projectId: 'p',
        targetLanguageId: 'l',
      );
      expect(settings.toJson()['format'], 'excel');
      for (final entry in {
        'csv': ImportFormat.csv,
        'json': ImportFormat.json,
        'excel': ImportFormat.excel,
        'loc': ImportFormat.loc,
      }.entries) {
        final decoded = ImportSettings.fromJson({
          'format': entry.key,
          'project_id': 'p',
          'target_language_id': 'l',
        });
        expect(decoded.format, entry.value);
      }
    });

    test('ImportColumn maps each value', () {
      expect(ImportColumn.values, hasLength(7));
      final settings = ImportSettings(
        format: ImportFormat.csv,
        projectId: 'p',
        targetLanguageId: 'l',
        columnMapping: {
          'a': ImportColumn.key,
          'b': ImportColumn.sourceText,
          'c': ImportColumn.targetText,
          'd': ImportColumn.status,
          'e': ImportColumn.notes,
          'f': ImportColumn.context,
          'g': ImportColumn.skip,
        },
      );
      final json = settings.toJson()['column_mapping'] as Map<String, dynamic>;
      expect(json['a'], 'key');
      expect(json['b'], 'source_text');
      expect(json['c'], 'target_text');
      expect(json['d'], 'status');
      expect(json['e'], 'notes');
      expect(json['f'], 'context');
      expect(json['g'], 'skip');
    });

    test('ConflictResolutionStrategy maps each value', () {
      expect(ConflictResolutionStrategy.values, hasLength(5));
      for (final entry in {
        'skip_existing': ConflictResolutionStrategy.skipExisting,
        'overwrite': ConflictResolutionStrategy.overwrite,
        'keep_newer': ConflictResolutionStrategy.keepNewer,
        'merge': ConflictResolutionStrategy.merge,
        'ask_me': ConflictResolutionStrategy.askMe,
      }.entries) {
        final decoded = ImportSettings.fromJson({
          'format': 'csv',
          'project_id': 'p',
          'target_language_id': 'l',
          'conflict_strategy': entry.key,
        });
        expect(decoded.conflictStrategy, entry.value);
      }
    });

    test('ExportFormat maps each value', () {
      expect(ExportFormat.values, hasLength(4));
      for (final entry in {
        'csv': ExportFormat.csv,
        'json': ExportFormat.json,
        'excel': ExportFormat.excel,
        'loc': ExportFormat.loc,
      }.entries) {
        final decoded = ExportSettings.fromJson({
          'format': entry.key,
          'project_id': 'p',
          'target_language_id': 'l',
        });
        expect(decoded.format, entry.value);
      }
    });

    test('ExportColumn maps each value', () {
      expect(ExportColumn.values, hasLength(9));
      final settings = ExportSettings(
        format: ExportFormat.csv,
        projectId: 'p',
        targetLanguageId: 'l',
        columns: const [
          ExportColumn.key,
          ExportColumn.sourceText,
          ExportColumn.targetText,
          ExportColumn.status,
          ExportColumn.notes,
          ExportColumn.context,
          ExportColumn.createdAt,
          ExportColumn.updatedAt,
          ExportColumn.changedBy,
        ],
      );
      expect(settings.toJson()['columns'], [
        'key',
        'source_text',
        'target_text',
        'status',
        'notes',
        'context',
        'created_at',
        'updated_at',
        'changed_by',
      ]);
    });
  });

  group('ImportSettings', () {
    test('constructor defaults', () {
      const settings = ImportSettings(
        format: ImportFormat.csv,
        projectId: 'p',
        targetLanguageId: 'l',
      );
      expect(settings.encoding, 'utf-8');
      expect(settings.hasHeaderRow, isTrue);
      expect(settings.columnMapping, isEmpty);
      expect(settings.conflictStrategy, ConflictResolutionStrategy.skipExisting);
      expect(settings.validationOptions, isA<ImportValidationOptions>());
    });

    test('copyWith overrides each field', () {
      const base = ImportSettings(
        format: ImportFormat.csv,
        projectId: 'p',
        targetLanguageId: 'l',
      );
      expect(base.copyWith(format: ImportFormat.json).format, ImportFormat.json);
      expect(base.copyWith(projectId: 'z').projectId, 'z');
      expect(base.copyWith(targetLanguageId: 'z').targetLanguageId, 'z');
      expect(base.copyWith(encoding: 'utf-16').encoding, 'utf-16');
      expect(base.copyWith(hasHeaderRow: false).hasHeaderRow, isFalse);
      expect(
        base.copyWith(columnMapping: {'k': ImportColumn.key}).columnMapping,
        {'k': ImportColumn.key},
      );
      expect(
        base
            .copyWith(conflictStrategy: ConflictResolutionStrategy.overwrite)
            .conflictStrategy,
        ConflictResolutionStrategy.overwrite,
      );
      final opts = const ImportValidationOptions(checkDuplicates: false);
      expect(base.copyWith(validationOptions: opts).validationOptions, opts);
    });

    test('copyWith with no args preserves values', () {
      const base = ImportSettings(
        format: ImportFormat.excel,
        projectId: 'p',
        targetLanguageId: 'l',
        encoding: 'utf-16',
        hasHeaderRow: false,
      );
      final copy = base.copyWith();
      expect(copy.format, base.format);
      expect(copy.projectId, base.projectId);
      expect(copy.targetLanguageId, base.targetLanguageId);
      expect(copy.encoding, base.encoding);
      expect(copy.hasHeaderRow, base.hasHeaderRow);
    });

    test('JSON round-trips including nested validation options', () {
      const original = ImportSettings(
        format: ImportFormat.json,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        encoding: 'utf-16',
        hasHeaderRow: false,
        columnMapping: {'key': ImportColumn.key, 'src': ImportColumn.sourceText},
        conflictStrategy: ConflictResolutionStrategy.keepNewer,
        validationOptions: ImportValidationOptions(checkDuplicates: false),
      );
      final decoded = ImportSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.format, ImportFormat.json);
      expect(decoded.projectId, 'proj-1');
      expect(decoded.targetLanguageId, 'lang_fr');
      expect(decoded.encoding, 'utf-16');
      expect(decoded.hasHeaderRow, isFalse);
      expect(decoded.columnMapping, original.columnMapping);
      expect(decoded.conflictStrategy, ConflictResolutionStrategy.keepNewer);
      expect(decoded.validationOptions.checkDuplicates, isFalse);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = ImportSettings.fromJson({
        'format': 'csv',
        'project_id': 'p',
        'target_language_id': 'l',
      });
      expect(decoded.encoding, 'utf-8');
      expect(decoded.hasHeaderRow, isTrue);
      expect(decoded.columnMapping, isEmpty);
      expect(decoded.conflictStrategy, ConflictResolutionStrategy.skipExisting);
      expect(decoded.validationOptions.validateColumns, isTrue);
    });
  });

  group('ImportValidationOptions', () {
    test('constructor defaults everything to true', () {
      const opts = ImportValidationOptions();
      expect(opts.checkDuplicates, isTrue);
      expect(opts.validateColumns, isTrue);
      expect(opts.warnSourceMismatch, isTrue);
      expect(opts.validateLanguage, isTrue);
    });

    test('copyWith overrides each field', () {
      const base = ImportValidationOptions();
      expect(base.copyWith(checkDuplicates: false).checkDuplicates, isFalse);
      expect(base.copyWith(validateColumns: false).validateColumns, isFalse);
      expect(base.copyWith(warnSourceMismatch: false).warnSourceMismatch,
          isFalse);
      expect(base.copyWith(validateLanguage: false).validateLanguage, isFalse);
    });

    test('copyWith with no args preserves values', () {
      const base = ImportValidationOptions(
        checkDuplicates: false,
        warnSourceMismatch: false,
      );
      final copy = base.copyWith();
      expect(copy.checkDuplicates, isFalse);
      expect(copy.validateColumns, isTrue);
      expect(copy.warnSourceMismatch, isFalse);
      expect(copy.validateLanguage, isTrue);
    });

    test('JSON round-trips', () {
      const original = ImportValidationOptions(
        checkDuplicates: false,
        validateColumns: false,
        warnSourceMismatch: true,
        validateLanguage: false,
      );
      final json = original.toJson();
      expect(json['check_duplicates'], isFalse);
      expect(json['validate_columns'], isFalse);
      expect(json['warn_source_mismatch'], isTrue);
      expect(json['validate_language'], isFalse);
      final decoded = ImportValidationOptions.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.checkDuplicates, isFalse);
      expect(decoded.validateColumns, isFalse);
      expect(decoded.warnSourceMismatch, isTrue);
      expect(decoded.validateLanguage, isFalse);
    });
  });

  group('ExportSettings', () {
    test('constructor default columns', () {
      const settings = ExportSettings(
        format: ExportFormat.csv,
        projectId: 'p',
        targetLanguageId: 'l',
      );
      expect(settings.columns, const [
        ExportColumn.key,
        ExportColumn.sourceText,
        ExportColumn.targetText,
        ExportColumn.status,
      ]);
      expect(settings.filterOptions, isA<ExportFilterOptions>());
      expect(settings.formatOptions, isA<ExportFormatOptions>());
    });

    test('copyWith overrides each field', () {
      const base = ExportSettings(
        format: ExportFormat.csv,
        projectId: 'p',
        targetLanguageId: 'l',
      );
      expect(base.copyWith(format: ExportFormat.excel).format,
          ExportFormat.excel);
      expect(base.copyWith(projectId: 'z').projectId, 'z');
      expect(base.copyWith(targetLanguageId: 'z').targetLanguageId, 'z');
      expect(
        base.copyWith(columns: const [ExportColumn.key]).columns,
        const [ExportColumn.key],
      );
      const filter = ExportFilterOptions(translationsOnly: true);
      expect(base.copyWith(filterOptions: filter).filterOptions, filter);
      const fmt = ExportFormatOptions(prettyPrint: false);
      expect(base.copyWith(formatOptions: fmt).formatOptions, fmt);
    });

    test('copyWith with no args preserves values', () {
      const base = ExportSettings(
        format: ExportFormat.json,
        projectId: 'p',
        targetLanguageId: 'l',
      );
      final copy = base.copyWith();
      expect(copy.format, base.format);
      expect(copy.projectId, base.projectId);
      expect(copy.targetLanguageId, base.targetLanguageId);
      expect(copy.columns, base.columns);
    });

    test('JSON round-trips including nested filter/format options', () {
      const original = ExportSettings(
        format: ExportFormat.json,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        columns: [ExportColumn.key, ExportColumn.targetText],
        filterOptions: ExportFilterOptions(
          statusFilter: ['translated'],
          contextFilter: 'campaign',
          translationsOnly: true,
          validatedOnly: true,
          createdAfter: 100,
          updatedAfter: 200,
        ),
        formatOptions: ExportFormatOptions(
          includeHeader: false,
          prettyPrint: false,
          encoding: 'utf-16',
          locPrefix: 'PREFIX',
        ),
      );
      final decoded = ExportSettings.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.format, ExportFormat.json);
      expect(decoded.columns, const [ExportColumn.key, ExportColumn.targetText]);
      expect(decoded.filterOptions.statusFilter, const ['translated']);
      expect(decoded.filterOptions.contextFilter, 'campaign');
      expect(decoded.filterOptions.translationsOnly, isTrue);
      expect(decoded.filterOptions.validatedOnly, isTrue);
      expect(decoded.filterOptions.createdAfter, 100);
      expect(decoded.filterOptions.updatedAfter, 200);
      expect(decoded.formatOptions.includeHeader, isFalse);
      expect(decoded.formatOptions.prettyPrint, isFalse);
      expect(decoded.formatOptions.encoding, 'utf-16');
      expect(decoded.formatOptions.locPrefix, 'PREFIX');
    });
  });

  group('ExportFilterOptions', () {
    test('constructor defaults', () {
      const opts = ExportFilterOptions();
      expect(opts.statusFilter, isNull);
      expect(opts.contextFilter, isNull);
      expect(opts.translationsOnly, isFalse);
      expect(opts.validatedOnly, isFalse);
      expect(opts.createdAfter, isNull);
      expect(opts.updatedAfter, isNull);
    });

    test('copyWith overrides each field', () {
      const base = ExportFilterOptions();
      expect(base.copyWith(statusFilter: const ['a']).statusFilter, const ['a']);
      expect(base.copyWith(contextFilter: 'ctx').contextFilter, 'ctx');
      expect(base.copyWith(translationsOnly: true).translationsOnly, isTrue);
      expect(base.copyWith(validatedOnly: true).validatedOnly, isTrue);
      expect(base.copyWith(createdAfter: 5).createdAfter, 5);
      expect(base.copyWith(updatedAfter: 6).updatedAfter, 6);
    });

    test('copyWith with no args preserves values', () {
      const base = ExportFilterOptions(
        statusFilter: ['translated'],
        translationsOnly: true,
      );
      final copy = base.copyWith();
      expect(copy.statusFilter, base.statusFilter);
      expect(copy.translationsOnly, isTrue);
    });

    test('JSON round-trips with nulls', () {
      const original = ExportFilterOptions();
      final decoded = ExportFilterOptions.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.statusFilter, isNull);
      expect(decoded.contextFilter, isNull);
      expect(decoded.translationsOnly, isFalse);
      expect(decoded.createdAfter, isNull);
    });
  });

  group('ExportFormatOptions', () {
    test('constructor defaults', () {
      const opts = ExportFormatOptions();
      expect(opts.includeHeader, isTrue);
      expect(opts.prettyPrint, isTrue);
      expect(opts.encoding, 'utf-8');
      expect(opts.locPrefix, isNull);
    });

    test('copyWith overrides each field', () {
      const base = ExportFormatOptions();
      expect(base.copyWith(includeHeader: false).includeHeader, isFalse);
      expect(base.copyWith(prettyPrint: false).prettyPrint, isFalse);
      expect(base.copyWith(encoding: 'utf-16').encoding, 'utf-16');
      expect(base.copyWith(locPrefix: 'P').locPrefix, 'P');
    });

    test('copyWith with no args preserves values', () {
      const base = ExportFormatOptions(includeHeader: false, locPrefix: 'X');
      final copy = base.copyWith();
      expect(copy.includeHeader, isFalse);
      expect(copy.prettyPrint, isTrue);
      expect(copy.encoding, 'utf-8');
      expect(copy.locPrefix, 'X');
    });

    test('JSON round-trips', () {
      const original = ExportFormatOptions(
        includeHeader: false,
        prettyPrint: false,
        encoding: 'utf-16',
        locPrefix: 'PRE',
      );
      final json = original.toJson();
      expect(json['include_header'], isFalse);
      expect(json['loc_prefix'], 'PRE');
      final decoded = ExportFormatOptions.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.includeHeader, isFalse);
      expect(decoded.prettyPrint, isFalse);
      expect(decoded.encoding, 'utf-16');
      expect(decoded.locPrefix, 'PRE');
    });
  });
}
