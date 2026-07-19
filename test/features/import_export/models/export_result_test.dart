import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/export_result.dart';

/// Unit tests for [ExportResult] and [ExportPreview] (json_serializable data
/// classes). Covers constructor defaults, the size/duration formatting getters
/// (every branch), `copyWith`, and JSON round-trips. Neither model overrides
/// `==`, so JSON assertions compare field-by-field.
void main() {
  group('ExportResult', () {
    ExportResult make({
      String filePath = 'C:/out.csv',
      int rowCount = 10,
      int fileSize = 512,
      int durationMs = 250,
      bool isSuccess = true,
      String? errorMessage,
    }) {
      return ExportResult(
        filePath: filePath,
        rowCount: rowCount,
        fileSize: fileSize,
        durationMs: durationMs,
        isSuccess: isSuccess,
        errorMessage: errorMessage,
      );
    }

    test('constructor defaults isSuccess=true and errorMessage=null', () {
      const result = ExportResult(
        filePath: 'f',
        rowCount: 0,
        fileSize: 0,
        durationMs: 0,
      );
      expect(result.isSuccess, isTrue);
      expect(result.errorMessage, isNull);
    });

    group('fileSizeFormatted', () {
      test('bytes below 1 KB', () {
        expect(make(fileSize: 512).fileSizeFormatted, '512 B');
      });
      test('kilobytes below 1 MB', () {
        expect(make(fileSize: 1536).fileSizeFormatted, '1.5 KB');
      });
      test('megabytes below 1 GB', () {
        expect(make(fileSize: 3 * 1024 * 1024).fileSizeFormatted, '3.0 MB');
      });
      test('gigabytes at or above 1 GB', () {
        expect(
          make(fileSize: 4 * 1024 * 1024 * 1024).fileSizeFormatted,
          '4.0 GB',
        );
      });
    });

    group('durationFormatted', () {
      test('milliseconds below 1 second', () {
        expect(make(durationMs: 250).durationFormatted, '250ms');
        expect(make(durationMs: 999).durationFormatted, '999ms');
      });
      test('seconds below 1 minute', () {
        expect(make(durationMs: 1500).durationFormatted, '1.5s');
        expect(make(durationMs: 59000).durationFormatted, '59.0s');
      });
      test('minutes at or above 1 minute', () {
        expect(make(durationMs: 90000).durationFormatted, '1.5m');
      });
    });

    group('copyWith', () {
      test('overrides each field', () {
        final base = make();
        expect(base.copyWith(filePath: 'x').filePath, 'x');
        expect(base.copyWith(rowCount: 99).rowCount, 99);
        expect(base.copyWith(fileSize: 99).fileSize, 99);
        expect(base.copyWith(durationMs: 99).durationMs, 99);
        expect(base.copyWith(isSuccess: false).isSuccess, isFalse);
        expect(base.copyWith(errorMessage: 'boom').errorMessage, 'boom');
      });

      test('unset fields fall back to current values', () {
        final base = make(errorMessage: 'e');
        final copy = base.copyWith(rowCount: 5);
        expect(copy.filePath, base.filePath);
        expect(copy.fileSize, base.fileSize);
        expect(copy.durationMs, base.durationMs);
        expect(copy.isSuccess, base.isSuccess);
        expect(copy.errorMessage, base.errorMessage);
      });
    });

    group('JSON', () {
      test('toJson uses snake_case keys', () {
        final json = make(errorMessage: 'oops').toJson();
        expect(json['file_path'], 'C:/out.csv');
        expect(json['row_count'], 10);
        expect(json['file_size'], 512);
        expect(json['duration_ms'], 250);
        expect(json['is_success'], isTrue);
        expect(json['error_message'], 'oops');
      });

      test('round-trips through jsonEncode/jsonDecode', () {
        final original = make(isSuccess: false, errorMessage: 'failed');
        final decoded = ExportResult.fromJson(
          jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
        );
        expect(decoded.filePath, original.filePath);
        expect(decoded.rowCount, original.rowCount);
        expect(decoded.fileSize, original.fileSize);
        expect(decoded.durationMs, original.durationMs);
        expect(decoded.isSuccess, original.isSuccess);
        expect(decoded.errorMessage, original.errorMessage);
      });

      test('fromJson applies default isSuccess when missing', () {
        final decoded = ExportResult.fromJson({
          'file_path': 'f',
          'row_count': 0,
          'file_size': 0,
          'duration_ms': 0,
        });
        expect(decoded.isSuccess, isTrue);
        expect(decoded.errorMessage, isNull);
      });
    });
  });

  group('ExportPreview', () {
    ExportPreview make({
      List<Map<String, String>>? previewRows,
      int totalRows = 5,
      int estimatedSize = 2048,
      List<String>? headers,
    }) {
      return ExportPreview(
        previewRows: previewRows ??
            const [
              {'key': 'K1', 'source_text': 'Hello'},
            ],
        totalRows: totalRows,
        estimatedSize: estimatedSize,
        headers: headers ?? const ['key', 'source_text'],
      );
    }

    group('estimatedSizeFormatted', () {
      test('bytes below 1 KB', () {
        expect(make(estimatedSize: 100).estimatedSizeFormatted, '100 B');
      });
      test('kilobytes below 1 MB', () {
        expect(make(estimatedSize: 2048).estimatedSizeFormatted, '2.0 KB');
      });
      test('megabytes below 1 GB', () {
        expect(
          make(estimatedSize: 2 * 1024 * 1024).estimatedSizeFormatted,
          '2.0 MB',
        );
      });
      test('gigabytes at or above 1 GB', () {
        expect(
          make(estimatedSize: 1024 * 1024 * 1024).estimatedSizeFormatted,
          '1.0 GB',
        );
      });
    });

    group('copyWith', () {
      test('overrides each field', () {
        final base = make();
        expect(
          base.copyWith(previewRows: const [
            {'a': 'b'},
          ]).previewRows,
          const [
            {'a': 'b'},
          ],
        );
        expect(base.copyWith(totalRows: 42).totalRows, 42);
        expect(base.copyWith(estimatedSize: 42).estimatedSize, 42);
        expect(base.copyWith(headers: const ['z']).headers, const ['z']);
      });

      test('unset fields fall back to current values', () {
        final base = make();
        final copy = base.copyWith(totalRows: 7);
        expect(copy.previewRows, base.previewRows);
        expect(copy.estimatedSize, base.estimatedSize);
        expect(copy.headers, base.headers);
      });
    });

    test('JSON round-trips through jsonEncode/jsonDecode', () {
      final original = make();
      final json = original.toJson();
      expect(json['total_rows'], 5);
      expect(json['estimated_size'], 2048);
      final decoded = ExportPreview.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
      );
      expect(decoded.previewRows, original.previewRows);
      expect(decoded.totalRows, original.totalRows);
      expect(decoded.estimatedSize, original.estimatedSize);
      expect(decoded.headers, original.headers);
    });
  });
}
