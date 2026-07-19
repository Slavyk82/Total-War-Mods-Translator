import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_preview.dart';

/// Unit tests for [ImportPreview] (json_serializable data class).
///
/// Covers constructor defaults, the human-readable `fileSizeFormatted`
/// getter's four size branches, `copyWith` field overrides, and the JSON
/// round-trip. The model has no `==` override, so JSON assertions compare
/// field-by-field rather than by value equality.
void main() {
  ImportPreview make({
    String filePath = 'C:/tmp/import.csv',
    List<String>? headers,
    List<Map<String, String>>? previewRows,
    int totalRows = 3,
    int fileSize = 512,
    String encoding = 'utf-8',
    Map<String, String>? suggestedMapping,
    String? contentHash = 'abc123',
  }) {
    return ImportPreview(
      filePath: filePath,
      headers: headers ?? const ['key', 'source', 'target'],
      previewRows: previewRows ??
          const [
            {'key': 'K1', 'source': 'Hello', 'target': 'Bonjour'},
          ],
      totalRows: totalRows,
      fileSize: fileSize,
      encoding: encoding,
      suggestedMapping:
          suggestedMapping ?? const {'key': 'key', 'source': 'source_text'},
      contentHash: contentHash,
    );
  }

  group('constructor defaults', () {
    test('suggestedMapping defaults to empty and contentHash to null', () {
      const preview = ImportPreview(
        filePath: 'f.csv',
        headers: ['a'],
        previewRows: [],
        totalRows: 0,
        fileSize: 0,
        encoding: 'utf-8',
      );
      expect(preview.suggestedMapping, isEmpty);
      expect(preview.contentHash, isNull);
    });
  });

  group('fileSizeFormatted', () {
    test('bytes below 1 KB', () {
      expect(make(fileSize: 512).fileSizeFormatted, '512 B');
      expect(make(fileSize: 0).fileSizeFormatted, '0 B');
      expect(make(fileSize: 1023).fileSizeFormatted, '1023 B');
    });

    test('kilobytes below 1 MB', () {
      expect(make(fileSize: 2048).fileSizeFormatted, '2.0 KB');
      expect(make(fileSize: 1536).fileSizeFormatted, '1.5 KB');
    });

    test('megabytes below 1 GB', () {
      expect(make(fileSize: 5 * 1024 * 1024).fileSizeFormatted, '5.0 MB');
    });

    test('gigabytes at or above 1 GB', () {
      expect(make(fileSize: 2 * 1024 * 1024 * 1024).fileSizeFormatted, '2.0 GB');
    });
  });

  group('copyWith', () {
    test('overrides each field', () {
      final base = make();
      expect(base.copyWith(filePath: 'x').filePath, 'x');
      expect(base.copyWith(headers: const ['z']).headers, const ['z']);
      expect(
        base.copyWith(previewRows: const [
          {'a': 'b'},
        ]).previewRows,
        const [
          {'a': 'b'},
        ],
      );
      expect(base.copyWith(totalRows: 99).totalRows, 99);
      expect(base.copyWith(fileSize: 99).fileSize, 99);
      expect(base.copyWith(encoding: 'utf-16').encoding, 'utf-16');
      expect(
        base.copyWith(suggestedMapping: const {'a': 'b'}).suggestedMapping,
        const {'a': 'b'},
      );
      expect(base.copyWith(contentHash: 'zzz').contentHash, 'zzz');
    });

    test('unset fields fall back to current values', () {
      final base = make();
      final copy = base.copyWith(totalRows: 7);
      expect(copy.filePath, base.filePath);
      expect(copy.headers, base.headers);
      expect(copy.previewRows, base.previewRows);
      expect(copy.fileSize, base.fileSize);
      expect(copy.encoding, base.encoding);
      expect(copy.suggestedMapping, base.suggestedMapping);
      expect(copy.contentHash, base.contentHash);
    });
  });

  group('JSON', () {
    test('toJson uses snake_case keys', () {
      final json = make().toJson();
      expect(json['file_path'], 'C:/tmp/import.csv');
      expect(json['total_rows'], 3);
      expect(json['file_size'], 512);
      expect(json['suggested_mapping'], isA<Map<String, String>>());
      expect(json['content_hash'], 'abc123');
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final original = make();
      final decoded = ImportPreview.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(decoded.filePath, original.filePath);
      expect(decoded.headers, original.headers);
      expect(decoded.previewRows, original.previewRows);
      expect(decoded.totalRows, original.totalRows);
      expect(decoded.fileSize, original.fileSize);
      expect(decoded.encoding, original.encoding);
      expect(decoded.suggestedMapping, original.suggestedMapping);
      expect(decoded.contentHash, original.contentHash);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = ImportPreview.fromJson({
        'file_path': 'f.csv',
        'headers': <String>['a'],
        'preview_rows': <Map<String, String>>[],
        'total_rows': 0,
        'file_size': 0,
        'encoding': 'utf-8',
      });
      expect(decoded.suggestedMapping, isEmpty);
      expect(decoded.contentHash, isNull);
    });
  });
}
