import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/file_import_export_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/utils/utf16_codec.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

void main() {
  late FileImportExportService service;
  late Directory tempDir;

  setUp(() async {
    // Register a fake ILoggingService so the no-logger factory path (which
    // falls back to ServiceLocator.get) works for the singleton test.
    await TestBootstrap.registerFakes(logger: NoopLogger());
    // A non-null logger forces a fresh, injected instance (not the singleton).
    service = FileImportExportService(logger: NoopLogger());
    tempDir = Directory.systemTemp.createTempSync('fileimpexp_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String pathIn(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  // ==========================================================================
  // CSV IMPORT
  // ==========================================================================
  group('importFromCsv', () {
    test('returns Err when file does not exist', () async {
      final result = await service.importFromCsv(
        filePath: pathIn('missing.csv'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ImportException;
      expect(err.format, 'csv');
      expect(err.message, contains('not found'));
    });

    test('parses header + rows on happy path', () async {
      final file = File(pathIn('data.csv'));
      file.writeAsStringSync('key,text\nhello,world\nfoo,bar\n');

      final result = await service.importFromCsv(filePath: file.path);

      expect(result.isOk, isTrue);
      final rows = result.value;
      expect(rows, hasLength(2));
      expect(rows[0], {'key': 'hello', 'text': 'world'});
      expect(rows[1], {'key': 'foo', 'text': 'bar'});
    });

    test('generates col_N headers when hasHeader is false', () async {
      final file = File(pathIn('noheader.csv'));
      file.writeAsStringSync('a,b\nc,d\n');

      final result = await service.importFromCsv(
        filePath: file.path,
        hasHeader: false,
      );

      expect(result.isOk, isTrue);
      final rows = result.value;
      expect(rows, hasLength(2));
      expect(rows[0], {'col_0': 'a', 'col_1': 'b'});
      expect(rows[1], {'col_0': 'c', 'col_1': 'd'});
    });

    test('returns empty list when file is empty/whitespace', () async {
      final file = File(pathIn('empty.csv'));
      file.writeAsStringSync('   \n  ');

      final result = await service.importFromCsv(filePath: file.path);

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('handles quoted fields with commas, quotes and newlines', () async {
      final file = File(pathIn('quoted.csv'));
      file.writeAsStringSync(
        'key,text\n'
        'a,"hello, world"\n'
        'b,"line1\nline2"\n'
        'c,"say ""hi"""\n'
        'd,""\n',
      );

      final result = await service.importFromCsv(filePath: file.path);

      expect(result.isOk, isTrue);
      final rows = result.value;
      expect(rows[0]['text'], 'hello, world');
      expect(rows[1]['text'], 'line1\nline2');
      expect(rows[2]['text'], 'say "hi"');
      // The "d" row has empty quoted text but non-empty key, so it is kept.
      expect(rows[3], {'key': 'd', 'text': ''});
    });

    test('skips completely empty data rows', () async {
      final file = File(pathIn('blanks.csv'));
      file.writeAsStringSync('key,text\nhello,world\n,\n\n');

      final result = await service.importFromCsv(filePath: file.path);

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('handles CRLF line endings', () async {
      final file = File(pathIn('crlf.csv'));
      file.writeAsStringSync('key,text\r\nhello,world\r\n');

      final result = await service.importFromCsv(filePath: file.path);

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
      expect(result.value[0], {'key': 'hello', 'text': 'world'});
    });

    test('strips a UTF-8 BOM', () async {
      final file = File(pathIn('bom.csv'));
      file.writeAsStringSync('﻿key,text\nhello,world\n');

      final result = await service.importFromCsv(filePath: file.path);

      expect(result.isOk, isTrue);
      // BOM stripped: first header is 'key', not '﻿key'.
      expect(result.value[0].containsKey('key'), isTrue);
    });

    test('decodes UTF-16LE with BOM', () async {
      final file = File(pathIn('utf16le.csv'));
      const text = 'key,text\nhé,wörld\n';
      final bytes = <int>[0xFF, 0xFE, ...const Utf16LeEncoder().convert(text)];
      file.writeAsBytesSync(bytes);

      final result = await service.importFromCsv(
        filePath: file.path,
        encoding: 'utf-16le',
      );

      expect(result.isOk, isTrue);
      expect(result.value[0], {'key': 'hé', 'text': 'wörld'});
    });

    test('decodes UTF-16BE with BOM via utf-16 auto-detect', () async {
      final file = File(pathIn('utf16be.csv'));
      const text = 'key,text\nhé,wörld\n';
      final bytes = <int>[0xFE, 0xFF, ...const Utf16BeEncoder().convert(text)];
      file.writeAsBytesSync(bytes);

      final result = await service.importFromCsv(
        filePath: file.path,
        encoding: 'utf-16',
      );

      expect(result.isOk, isTrue);
      expect(result.value[0], {'key': 'hé', 'text': 'wörld'});
    });

    test('decodes UTF-16 little-endian when no BOM present', () async {
      final file = File(pathIn('utf16nobom.csv'));
      const text = 'key,text\nh,w\n';
      file.writeAsBytesSync(const Utf16LeEncoder().convert(text));

      final result = await service.importFromCsv(
        filePath: file.path,
        encoding: 'utf-16',
      );

      expect(result.isOk, isTrue);
      expect(result.value[0], {'key': 'h', 'text': 'w'});
    });

    test('decodes explicit utf-16be without BOM', () async {
      final file = File(pathIn('utf16be_nobom.csv'));
      const text = 'key,text\nh,w\n';
      file.writeAsBytesSync(const Utf16BeEncoder().convert(text));

      final result = await service.importFromCsv(
        filePath: file.path,
        encoding: 'utf-16be',
      );

      expect(result.isOk, isTrue);
      expect(result.value[0], {'key': 'h', 'text': 'w'});
    });

    test('returns Err when path is a directory (FileSystemException)',
        () async {
      final dir = Directory(pathIn('a_dir'))..createSync();

      final result = await service.importFromCsv(filePath: dir.path);

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ImportException;
      expect(err.format, 'csv');
    });
  });

  // ==========================================================================
  // CSV EXPORT
  // ==========================================================================
  group('exportToCsv', () {
    test('returns Err when data is empty', () async {
      final result = await service.exportToCsv(
        data: [],
        filePath: pathIn('out.csv'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ExportException;
      expect(err.message, contains('No data'));
      expect(err.format, 'csv');
    });

    test('writes CSV with BOM and escaping, derives headers from first row',
        () async {
      final outPath = pathIn('out.csv');
      final result = await service.exportToCsv(
        data: [
          {'key': 'a', 'text': 'hello, world'},
          {'key': 'b', 'text': 'say "hi"'},
        ],
        filePath: outPath,
      );

      expect(result.isOk, isTrue);
      expect(result.value, outPath);

      // Read raw bytes so the BOM is not silently stripped on decode.
      final rawBytes = File(outPath).readAsBytesSync();
      expect(rawBytes.take(3), [0xEF, 0xBB, 0xBF]); // UTF-8 BOM
      final written = utf8.decode(rawBytes);
      expect(written, contains('"hello, world"'));
      expect(written, contains('"say ""hi"""'));

      // Round-trip back through import.
      final imported = await service.importFromCsv(filePath: outPath);
      expect(imported.value, hasLength(2));
      expect(imported.value[1]['text'], 'say "hi"');
    });

    test('honors explicit headers and missing keys become empty', () async {
      final outPath = pathIn('headers.csv');
      final result = await service.exportToCsv(
        data: [
          {'key': 'a', 'text': 'x'},
        ],
        filePath: outPath,
        headers: ['key', 'text', 'extra'],
      );

      expect(result.isOk, isTrue);
      final written = File(outPath).readAsStringSync();
      expect(written, contains('key,text,extra'));
    });

    test('creates parent directory when it does not exist', () async {
      final outPath = pathIn('nested${Platform.pathSeparator}deep'
          '${Platform.pathSeparator}out.csv');

      final result = await service.exportToCsv(
        data: [
          {'k': 'v'},
        ],
        filePath: outPath,
      );

      expect(result.isOk, isTrue);
      expect(File(outPath).existsSync(), isTrue);
    });

    test('returns Err when destination path is a directory', () async {
      final dir = Directory(pathIn('csv_target_dir'))..createSync();

      final result = await service.exportToCsv(
        data: [
          {'k': 'v'},
        ],
        filePath: dir.path,
      );

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<ExportException>());
    });
  });

  // ==========================================================================
  // JSON IMPORT
  // ==========================================================================
  group('importFromJson', () {
    test('returns Err when file does not exist', () async {
      final result = await service.importFromJson(
        filePath: pathIn('missing.json'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ImportException;
      expect(err.format, 'json');
      expect(err.message, contains('not found'));
    });

    test('parses valid JSON object', () async {
      final file = File(pathIn('obj.json'));
      file.writeAsStringSync('{"a": 1, "b": [2, 3]}');

      final result = await service.importFromJson(filePath: file.path);

      expect(result.isOk, isTrue);
      expect(result.value, {'a': 1, 'b': [2, 3]});
    });

    test('returns Err on invalid JSON (FormatException)', () async {
      final file = File(pathIn('bad.json'));
      file.writeAsStringSync('{not valid json');

      final result = await service.importFromJson(filePath: file.path);

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ImportException;
      expect(err.message, contains('Invalid JSON'));
    });

    test('decodes UTF-16LE JSON honoring encoding', () async {
      final file = File(pathIn('u16.json'));
      const json = '{"name": "wörld"}';
      final bytes = <int>[0xFF, 0xFE, ...const Utf16LeEncoder().convert(json)];
      file.writeAsBytesSync(bytes);

      final result = await service.importFromJson(
        filePath: file.path,
        encoding: 'utf-16le',
      );

      expect(result.isOk, isTrue);
      expect(result.value, {'name': 'wörld'});
    });

    test('returns generic Err when path is a directory', () async {
      final dir = Directory(pathIn('json_dir'))..createSync();

      final result = await service.importFromJson(filePath: dir.path);

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<ImportException>());
    });
  });

  // ==========================================================================
  // JSON EXPORT
  // ==========================================================================
  group('exportToJson', () {
    test('pretty-prints by default', () async {
      final outPath = pathIn('pretty.json');
      final result = await service.exportToJson(
        data: {'a': 1, 'b': 2},
        filePath: outPath,
      );

      expect(result.isOk, isTrue);
      expect(result.value, outPath);
      final written = File(outPath).readAsStringSync();
      expect(written, contains('\n')); // indentation produces newlines
      expect(jsonDecode(written), {'a': 1, 'b': 2});
    });

    test('compact output when prettyPrint is false', () async {
      final outPath = pathIn('compact.json');
      final result = await service.exportToJson(
        data: {'a': 1},
        filePath: outPath,
        prettyPrint: false,
      );

      expect(result.isOk, isTrue);
      final written = File(outPath).readAsStringSync();
      expect(written, '{"a":1}');
    });

    test('creates parent directory when missing', () async {
      final outPath = pathIn('jnested${Platform.pathSeparator}out.json');
      final result = await service.exportToJson(
        data: [1, 2, 3],
        filePath: outPath,
      );

      expect(result.isOk, isTrue);
      expect(File(outPath).existsSync(), isTrue);
    });

    test('returns Err for unencodable data (JsonUnsupportedObjectError)',
        () async {
      final result = await service.exportToJson(
        data: Object(), // a plain object is not JSON encodable
        filePath: pathIn('bad.json'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ExportException;
      expect(err.format, 'json');
    });

    test('returns Err when destination path is a directory', () async {
      final dir = Directory(pathIn('json_out_dir'))..createSync();

      final result = await service.exportToJson(
        data: {'a': 1},
        filePath: dir.path,
      );

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<ExportException>());
    });
  });

  // ==========================================================================
  // EXCEL IMPORT / EXPORT (round trip)
  // ==========================================================================
  group('Excel', () {
    /// Build a real .xlsx file at [filePath] with the given rows.
    void writeExcel(String filePath, List<List<String?>> rows,
        {String sheetName = 'Sheet1'}) {
      final excel = Excel.createExcel();
      if (excel.tables.containsKey('Sheet1') && sheetName != 'Sheet1') {
        excel.delete('Sheet1');
      }
      final sheet = excel[sheetName];
      for (final row in rows) {
        sheet.appendRow(
          row.map<CellValue?>((v) => v == null ? null : TextCellValue(v))
              .toList(),
        );
      }
      final bytes = excel.encode()!;
      File(filePath).writeAsBytesSync(bytes);
    }

    test('importFromExcel returns Err when file does not exist', () async {
      final result = await service.importFromExcel(
        filePath: pathIn('missing.xlsx'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ImportException;
      expect(err.format, 'excel');
      expect(err.message, contains('not found'));
    });

    test('importFromExcel parses header + rows', () async {
      final p = pathIn('book.xlsx');
      writeExcel(p, [
        ['key', 'text'],
        ['hello', 'world'],
        ['foo', 'bar'],
      ]);

      final result = await service.importFromExcel(filePath: p);

      expect(result.isOk, isTrue);
      final rows = result.value;
      expect(rows, hasLength(2));
      expect(rows[0]['key'], 'hello');
      expect(rows[1]['text'], 'bar');
    });

    test('importFromExcel generates col_N when hasHeader false', () async {
      final p = pathIn('nohead.xlsx');
      writeExcel(p, [
        ['a', 'b'],
        ['c', 'd'],
      ]);

      final result = await service.importFromExcel(
        filePath: p,
        hasHeader: false,
      );

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(2));
      expect(result.value[0], {'col_0': 'a', 'col_1': 'b'});
    });

    test('importFromExcel skips empty rows', () async {
      final p = pathIn('empties.xlsx');
      writeExcel(p, [
        ['key', 'text'],
        ['hello', 'world'],
        [null, null],
      ]);

      final result = await service.importFromExcel(filePath: p);

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('importFromExcel honors named sheet', () async {
      final p = pathIn('named.xlsx');
      writeExcel(p, [
        ['key', 'text'],
        ['x', 'y'],
      ], sheetName: 'Data');

      final result = await service.importFromExcel(
        filePath: p,
        sheetName: 'Data',
      );

      expect(result.isOk, isTrue);
      expect(result.value, hasLength(1));
    });

    test('importFromExcel returns Err for missing named sheet', () async {
      final p = pathIn('nosheet.xlsx');
      writeExcel(p, [
        ['key'],
        ['v'],
      ]);

      final result = await service.importFromExcel(
        filePath: p,
        sheetName: 'DoesNotExist',
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ImportException;
      expect(err.message, contains('not found'));
    });

    test('importFromExcel returns Err for non-xlsx bytes', () async {
      final p = pathIn('garbage.xlsx');
      File(p).writeAsStringSync('this is not a zip archive');

      final result = await service.importFromExcel(filePath: p);

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<ImportException>());
    });

    test('exportToExcel returns Err when data is empty', () async {
      final result = await service.exportToExcel(
        data: [],
        filePath: pathIn('out.xlsx'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error as ExportException;
      expect(err.message, contains('No data'));
    });

    test('exportToExcel writes a readable workbook (round trip)', () async {
      final outPath = pathIn('exported.xlsx');
      final data = [
        {'key': 'a', 'text': 'a fairly long cell value to widen the column'},
        {'key': 'b', 'text': 'short'},
      ];

      final result = await service.exportToExcel(
        data: data,
        filePath: outPath,
        sheetName: 'MySheet',
      );

      expect(result.isOk, isTrue);
      expect(result.value, outPath);
      expect(File(outPath).existsSync(), isTrue);

      final reImport = await service.importFromExcel(
        filePath: outPath,
        sheetName: 'MySheet',
      );
      expect(reImport.isOk, isTrue);
      expect(reImport.value, hasLength(2));
      expect(reImport.value[0]['key'], 'a');
    });

    test('exportToExcel honors explicit headers and creates parent dir',
        () async {
      final outPath = pathIn('xnested${Platform.pathSeparator}book.xlsx');

      final result = await service.exportToExcel(
        data: [
          {'key': 'a', 'text': 'x'},
        ],
        filePath: outPath,
        headers: ['key', 'text', 'extra'],
      );

      expect(result.isOk, isTrue);
      expect(File(outPath).existsSync(), isTrue);

      final reImport = await service.importFromExcel(filePath: outPath);
      expect(reImport.value[0].containsKey('extra'), isTrue);
    });

    test('exportToExcel returns Err when destination is a directory', () async {
      final dir = Directory(pathIn('excel_out_dir'))..createSync();

      final result = await service.exportToExcel(
        data: [
          {'k': 'v'},
        ],
        filePath: dir.path,
      );

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<ExportException>());
    });
  });

  // ==========================================================================
  // FACTORY
  // ==========================================================================
  test('factory returns shared singleton when no logger provided', () {
    final a = FileImportExportService();
    final b = FileImportExportService();
    expect(identical(a, b), isTrue);
  });
}
