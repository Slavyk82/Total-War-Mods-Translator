import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Unit tests for [ImportFileReader] with a mocked [IFileService] (mocktail),
/// so every format branch (CSV/JSON/Excel/.loc), the JSON-shape adapter
/// `_rowsFromJson`, the error/Err paths, the outer catch and
/// `detectColumnMapping` are exercised without touching disk or the database.
class _MockFileService extends Mock implements IFileService {}

void main() {
  late _MockFileService fileService;
  late ImportFileReader reader;

  setUp(() {
    fileService = _MockFileService();
    reader = ImportFileReader(fileService);
  });

  ImportSettings settings({
    ImportFormat format = ImportFormat.csv,
    bool hasHeaderRow = true,
    String encoding = 'utf-8',
  }) =>
      ImportSettings(
        format: format,
        projectId: 'p',
        targetLanguageId: 'l',
        hasHeaderRow: hasHeaderRow,
        encoding: encoding,
      );

  void stubCsv(Result<List<Map<String, String>>, ImportException> result) {
    when(() => fileService.importFromCsv(
          filePath: any(named: 'filePath'),
          hasHeader: any(named: 'hasHeader'),
          encoding: any(named: 'encoding'),
        )).thenAnswer((_) async => result);
  }

  void stubJson(Result<dynamic, ImportException> result) {
    when(() => fileService.importFromJson(
          filePath: any(named: 'filePath'),
          encoding: any(named: 'encoding'),
        )).thenAnswer((_) async => result);
  }

  void stubExcel(Result<List<Map<String, String>>, ImportException> result) {
    when(() => fileService.importFromExcel(
          filePath: any(named: 'filePath'),
          hasHeader: any(named: 'hasHeader'),
        )).thenAnswer((_) async => result);
  }

  group('CSV', () {
    test('reads rows and derives headers from the first row', () async {
      stubCsv(const Ok([
        {'key': 'K1', 'source': 'Hello'},
        {'key': 'K2', 'source': 'World'},
      ]));

      final result = await reader.readFile('f.csv', settings());

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.rows, hasLength(2));
      expect(result.value.headers, ['key', 'source']);
    });

    test('empty CSV yields empty rows and empty headers', () async {
      stubCsv(const Ok([]));

      final result = await reader.readFile('f.csv', settings());

      expect(result.isOk, isTrue);
      expect(result.value.rows, isEmpty);
      expect(result.value.headers, isEmpty);
    });

    test('Err is wrapped as "Failed to read CSV"', () async {
      stubCsv(Err(ImportException('broken', 'f.csv', 'csv')));

      final result = await reader.readFile('f.csv', settings());

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to read CSV'));
    });
  });

  group('JSON', () {
    test('top-level array of objects becomes rows', () async {
      stubJson(const Ok([
        {'key': 'K1', 'target': 'Bonjour'},
        {'key': 'K2', 'target': 'Salut'},
      ]));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.rows, hasLength(2));
      expect(result.value.rows.first['key'], 'K1');
      expect(result.value.headers, ['key', 'target']);
    });

    test('array with nulls and non-map entries: nulls become "" and '
        'non-maps are filtered', () async {
      stubJson(const Ok([
        {'key': 'K1', 'target': null},
        'not a map',
        {'key': 'K2', 'target': 'X'},
      ]));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isOk, isTrue);
      expect(result.value.rows, hasLength(2)); // string entry dropped
      expect(result.value.rows.first['target'], ''); // null -> ''
    });

    test('wrapper object with a single array property becomes rows', () async {
      stubJson(const Ok({
        'rows': [
          {'key': 'K1', 'target': 'Bonjour'},
        ],
      }));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isOk, isTrue);
      expect(result.value.rows, hasLength(1));
      expect(result.value.rows.first['key'], 'K1');
    });

    test('key->object map exposes the outer key as a "key" column', () async {
      stubJson(const Ok({
        'unit_a': {'source': 'Hello', 'target': 'Bonjour'},
        'unit_b': {'source': 'World', 'target': 'Monde'},
      }));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isOk, isTrue);
      expect(result.value.rows, hasLength(2));
      expect(result.value.rows[0]['key'], 'unit_a');
      expect(result.value.rows[0]['source'], 'Hello');
      expect(result.value.rows[1]['key'], 'unit_b');
    });

    test('key->object map does not clobber an existing inner "key"', () async {
      stubJson(const Ok({
        'unit_a': {'key': 'explicit', 'source': 'Hello'},
      }));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isOk, isTrue);
      expect(result.value.rows.single['key'], 'explicit');
    });

    test('empty object is an unsupported structure (error)', () async {
      stubJson(const Ok(<String, dynamic>{}));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Unsupported JSON structure'));
    });

    test('a bare scalar is an unsupported structure (error)', () async {
      stubJson(const Ok('just a string'));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Unsupported JSON structure'));
    });

    test('object with multiple array properties is unsupported (error)',
        () async {
      stubJson(const Ok({
        'a': [1],
        'b': [2],
      }));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Unsupported JSON structure'));
    });

    test('Err is wrapped as "Failed to read JSON"', () async {
      stubJson(Err(ImportException('broken', 'f.json', 'json')));

      final result =
          await reader.readFile('f.json', settings(format: ImportFormat.json));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to read JSON'));
    });
  });

  group('Excel', () {
    test('reads rows and derives headers', () async {
      stubExcel(const Ok([
        {'key': 'K1', 'source': 'Hello'},
      ]));

      final result =
          await reader.readFile('f.xlsx', settings(format: ImportFormat.excel));

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.rows, hasLength(1));
      expect(result.value.headers, ['key', 'source']);
    });

    test('Err is wrapped as "Failed to read Excel"', () async {
      stubExcel(Err(ImportException('broken', 'f.xlsx', 'excel')));

      final result =
          await reader.readFile('f.xlsx', settings(format: ImportFormat.excel));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to read Excel'));
    });
  });

  group('.loc', () {
    test('returns a not-implemented error', () async {
      final result =
          await reader.readFile('f.loc', settings(format: ImportFormat.loc));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not yet implemented'));
    });
  });

  group('outer catch', () {
    test('an unexpected throw from the file service is wrapped', () async {
      when(() => fileService.importFromCsv(
            filePath: any(named: 'filePath'),
            hasHeader: any(named: 'hasHeader'),
            encoding: any(named: 'encoding'),
          )).thenThrow(StateError('kaboom'));

      final result = await reader.readFile('f.csv', settings());

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to read file'));
    });
  });

  group('detectColumnMapping', () {
    test('maps recognizable headers to column types', () {
      final mapping = reader.detectColumnMapping([
        'Key',
        'source_text',
        'Target',
        'Status',
        'Notes',
        'Context',
      ]);
      expect(mapping['Key'], 'key');
      expect(mapping['source_text'], 'sourceText');
      expect(mapping['Target'], 'targetText');
      expect(mapping['Status'], 'status');
      expect(mapping['Notes'], 'notes');
      expect(mapping['Context'], 'context');
    });

    test('the exact header "id" maps to key', () {
      expect(reader.detectColumnMapping(['id'])['id'], 'key');
    });

    test('"translation" and "translated" both map to targetText', () {
      final mapping =
          reader.detectColumnMapping(['translation', 'translated']);
      expect(mapping['translation'], 'targetText');
      expect(mapping['translated'], 'targetText');
    });

    test('unrecognized headers are omitted from the mapping', () {
      final mapping = reader.detectColumnMapping(['irrelevant', 'foo']);
      expect(mapping, isEmpty);
    });
  });
}
