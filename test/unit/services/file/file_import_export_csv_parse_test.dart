import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/file_import_export_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

/// Regression tests for the hand-rolled CSV parser (_parseCsv), exercised
/// through the public [FileImportExportService.importFromCsv] API.
///
/// Bug fixed: the escaped-quote branch ("" -> ") fired even OUTSIDE quoted
/// fields, so an empty quoted field ("") decoded to a literal '"' instead
/// of the empty string (and """" decoded to '""' instead of '"').
void main() {
  late FileImportExportService service;
  late Directory tempDir;

  setUp(() async {
    service = FileImportExportService(logger: FakeLogger());
    tempDir = await Directory.systemTemp.createTemp('twmt_csv_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  var fileCounter = 0;

  Future<List<Map<String, String>>> importCsv(
    String content, {
    bool hasHeader = false,
  }) async {
    final file = File('${tempDir.path}\\case_${fileCounter++}.csv');
    await file.writeAsString(content);
    final result = await service.importFromCsv(
      filePath: file.path,
      hasHeader: hasHeader,
    );
    expect(result.isOk, isTrue, reason: 'import must succeed: $result');
    return result.value;
  }

  group('_parseCsv quoting (via importFromCsv, hasHeader: false)', () {
    // (input, expected single row as ordered field values)
    final cases = <String, List<String>>{
      // Empty quoted field must decode to the empty string, not '"'.
      'a,"",b': ['a', '', 'b'],
      // Same with every field quoted (pandas QUOTE_ALL / R write.csv style).
      '"a","","b"': ['a', '', 'b'],
      // Four quotes = quoted field containing one escaped quote.
      'a,"""",b': ['a', '"', 'b'],
      // Escaped quote embedded inside a quoted field.
      '"x""y",z': ['x"y', 'z'],
      // Quoted separator and quoted newline are preserved.
      '"a,b","c\nd",e': ['a,b', 'c\nd', 'e'],
      // Leading empty quoted field.
      '"",x': ['', 'x'],
    };

    cases.forEach((input, expectedFields) {
      test('parses ${input.replaceAll('\n', r'\n')} correctly', () async {
        final rows = await importCsv(input);

        expect(rows, hasLength(1));
        final expected = <String, String>{
          for (var i = 0; i < expectedFields.length; i++)
            'col_$i': expectedFields[i],
        };
        expect(rows.single, expected);
      });
    });

    test('a row of only empty quoted fields stays empty (and is skipped '
        'by the empty-row filter, not turned into literal quotes)', () async {
      final rows = await importCsv('"",""');
      expect(rows, isEmpty,
          reason: 'previously "","" decoded to two literal-quote fields '
              'which defeated the empty-row filter');
    });

    test('CRLF content with header: empty quoted column is empty', () async {
      final rows = await importCsv(
        'key,value\r\nk1,""\r\nk2,"v2"\r\n',
        hasHeader: true,
      );

      expect(rows, hasLength(2));
      expect(rows[0], {'key': 'k1', 'value': ''});
      expect(rows[1], {'key': 'k2', 'value': 'v2'});
    });
  });
}
