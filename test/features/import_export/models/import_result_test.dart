import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_result.dart';

/// Unit tests for [ImportResult] and [ImportValidationResult]
/// (json_serializable data classes). Covers constructor defaults, the
/// success/partial/failed computed getters, `durationFormatted` branches,
/// `hasIssues`, `copyWith`, and JSON round-trips. Neither model overrides
/// `==`, so JSON assertions compare field-by-field.
void main() {
  group('ImportResult', () {
    ImportResult make({
      int totalProcessed = 10,
      int successCount = 8,
      int skippedCount = 1,
      int errorCount = 1,
      Map<String, String>? errors,
      List<String>? importedIds,
      int durationMs = 250,
    }) {
      return ImportResult(
        totalProcessed: totalProcessed,
        successCount: successCount,
        skippedCount: skippedCount,
        errorCount: errorCount,
        errors: errors ?? const {'row-3': 'boom'},
        importedIds: importedIds ?? const ['v1', 'v2'],
        durationMs: durationMs,
      );
    }

    test('constructor defaults errors and importedIds to empty', () {
      const result = ImportResult(
        totalProcessed: 0,
        successCount: 0,
        skippedCount: 0,
        errorCount: 0,
        durationMs: 0,
      );
      expect(result.errors, isEmpty);
      expect(result.importedIds, isEmpty);
    });

    group('status getters', () {
      test('isSuccess true only when errorCount is zero', () {
        expect(make(errorCount: 0).isSuccess, isTrue);
        expect(make(errorCount: 1).isSuccess, isFalse);
      });

      test('isPartialSuccess true when some succeeded and some errored', () {
        expect(make(successCount: 5, errorCount: 2).isPartialSuccess, isTrue);
        expect(make(successCount: 0, errorCount: 2).isPartialSuccess, isFalse);
        expect(make(successCount: 5, errorCount: 0).isPartialSuccess, isFalse);
      });

      test('isFailed true only when nothing succeeded but there were errors',
          () {
        expect(make(successCount: 0, errorCount: 3).isFailed, isTrue);
        expect(make(successCount: 1, errorCount: 3).isFailed, isFalse);
        expect(make(successCount: 0, errorCount: 0).isFailed, isFalse);
      });
    });

    group('durationFormatted', () {
      test('milliseconds below 1 second', () {
        expect(make(durationMs: 300).durationFormatted, '300ms');
      });
      test('seconds below 1 minute', () {
        expect(make(durationMs: 2500).durationFormatted, '2.5s');
      });
      test('minutes at or above 1 minute', () {
        expect(make(durationMs: 120000).durationFormatted, '2.0m');
      });
    });

    group('copyWith', () {
      test('overrides each field', () {
        final base = make();
        expect(base.copyWith(totalProcessed: 99).totalProcessed, 99);
        expect(base.copyWith(successCount: 99).successCount, 99);
        expect(base.copyWith(skippedCount: 99).skippedCount, 99);
        expect(base.copyWith(errorCount: 99).errorCount, 99);
        expect(base.copyWith(errors: const {'x': 'y'}).errors, const {'x': 'y'});
        expect(
          base.copyWith(importedIds: const ['z']).importedIds,
          const ['z'],
        );
        expect(base.copyWith(durationMs: 99).durationMs, 99);
      });

      test('unset fields fall back to current values', () {
        final base = make();
        final copy = base.copyWith(successCount: 7);
        expect(copy.totalProcessed, base.totalProcessed);
        expect(copy.skippedCount, base.skippedCount);
        expect(copy.errorCount, base.errorCount);
        expect(copy.errors, base.errors);
        expect(copy.importedIds, base.importedIds);
        expect(copy.durationMs, base.durationMs);
      });
    });

    group('JSON', () {
      test('toJson uses snake_case keys', () {
        final json = make().toJson();
        expect(json['total_processed'], 10);
        expect(json['success_count'], 8);
        expect(json['skipped_count'], 1);
        expect(json['error_count'], 1);
        expect(json['errors'], const {'row-3': 'boom'});
        expect(json['imported_ids'], const ['v1', 'v2']);
        expect(json['duration_ms'], 250);
      });

      test('round-trips through jsonEncode/jsonDecode', () {
        final original = make();
        final decoded = ImportResult.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );
        expect(decoded.totalProcessed, original.totalProcessed);
        expect(decoded.successCount, original.successCount);
        expect(decoded.skippedCount, original.skippedCount);
        expect(decoded.errorCount, original.errorCount);
        expect(decoded.errors, original.errors);
        expect(decoded.importedIds, original.importedIds);
        expect(decoded.durationMs, original.durationMs);
      });

      test('fromJson applies defaults for missing errors/importedIds', () {
        final decoded = ImportResult.fromJson({
          'total_processed': 0,
          'success_count': 0,
          'skipped_count': 0,
          'error_count': 0,
          'duration_ms': 0,
        });
        expect(decoded.errors, isEmpty);
        expect(decoded.importedIds, isEmpty);
      });
    });
  });

  group('ImportValidationResult', () {
    ImportValidationResult make({
      bool isValid = true,
      List<String>? errors,
      List<String>? warnings,
      List<String>? duplicateKeys,
      List<String>? missingColumns,
    }) {
      return ImportValidationResult(
        isValid: isValid,
        errors: errors ?? const [],
        warnings: warnings ?? const [],
        duplicateKeys: duplicateKeys ?? const [],
        missingColumns: missingColumns ?? const [],
      );
    }

    test('constructor defaults all lists to empty', () {
      const result = ImportValidationResult(isValid: true);
      expect(result.errors, isEmpty);
      expect(result.warnings, isEmpty);
      expect(result.duplicateKeys, isEmpty);
      expect(result.missingColumns, isEmpty);
    });

    group('hasIssues', () {
      test('false when neither errors nor warnings present', () {
        expect(make().hasIssues, isFalse);
      });
      test('true when errors present', () {
        expect(make(errors: const ['e']).hasIssues, isTrue);
      });
      test('true when warnings present', () {
        expect(make(warnings: const ['w']).hasIssues, isTrue);
      });
    });

    group('copyWith', () {
      test('overrides each field', () {
        final base = make();
        expect(base.copyWith(isValid: false).isValid, isFalse);
        expect(base.copyWith(errors: const ['e']).errors, const ['e']);
        expect(base.copyWith(warnings: const ['w']).warnings, const ['w']);
        expect(
          base.copyWith(duplicateKeys: const ['d']).duplicateKeys,
          const ['d'],
        );
        expect(
          base.copyWith(missingColumns: const ['m']).missingColumns,
          const ['m'],
        );
      });

      test('unset fields fall back to current values', () {
        final base = make(
          isValid: false,
          errors: const ['e'],
          warnings: const ['w'],
        );
        final copy = base.copyWith(duplicateKeys: const ['d']);
        expect(copy.isValid, base.isValid);
        expect(copy.errors, base.errors);
        expect(copy.warnings, base.warnings);
        expect(copy.missingColumns, base.missingColumns);
      });
    });

    test('JSON round-trips through jsonEncode/jsonDecode', () {
      final original = make(
        isValid: false,
        errors: const ['e1'],
        warnings: const ['w1'],
        duplicateKeys: const ['K1'],
        missingColumns: const ['key'],
      );
      final json = original.toJson();
      expect(json['is_valid'], isFalse);
      expect(json['duplicate_keys'], const ['K1']);
      expect(json['missing_columns'], const ['key']);
      final decoded = ImportValidationResult.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.isValid, original.isValid);
      expect(decoded.errors, original.errors);
      expect(decoded.warnings, original.warnings);
      expect(decoded.duplicateKeys, original.duplicateKeys);
      expect(decoded.missingColumns, original.missingColumns);
    });

    test('fromJson applies defaults for missing optional lists', () {
      final decoded = ImportValidationResult.fromJson({'is_valid': true});
      expect(decoded.errors, isEmpty);
      expect(decoded.warnings, isEmpty);
      expect(decoded.duplicateKeys, isEmpty);
      expect(decoded.missingColumns, isEmpty);
    });
  });
}
