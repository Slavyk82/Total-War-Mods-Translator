import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/services/file/file_service_impl.dart';

import '../../../helpers/test_bootstrap.dart';

/// Regression tests: JSON import only handled a top-level array. A JSON file
/// whose root is an object — a key->object map, or a wrapper like
/// `{"rows": [...]}` (both common ways to store translations) — produced zero
/// rows and reported a *successful* import of nothing. Unsupported shapes must
/// now surface a clear error instead of a silent empty success.
void main() {
  late Directory tempDir;
  late ImportFileReader reader;

  setUp(() async {
    await TestBootstrap.registerFakes();
    tempDir = Directory.systemTemp.createTempSync('import_json_object_root');
    reader = ImportFileReader(FileServiceImpl());
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  ImportSettings jsonSettings() => const ImportSettings(
        format: ImportFormat.json,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        encoding: 'utf-8',
        hasHeaderRow: true,
        columnMapping: {},
      );

  Future<String> writeJson(Object json) async {
    final file = File('${tempDir.path}/data.json');
    await file.writeAsString(jsonEncode(json));
    return file.path;
  }

  test('key->object map root yields one row per entry with a key column',
      () async {
    final path = await writeJson({
      'unit_a': {'source': 'Sword', 'target': 'Épée'},
      'unit_b': {'source': 'Spear', 'target': 'Lance'},
    });

    final result = await reader.readFile(path, jsonSettings());

    expect(result.isOk, isTrue, reason: result.toString());
    final rows = result.value.rows;
    expect(rows, hasLength(2),
        reason: 'An object-root JSON must not import as zero rows');
    final byKey = {for (final r in rows) r['key']: r};
    expect(byKey['unit_a']!['source'], 'Sword');
    expect(byKey['unit_a']!['target'], 'Épée');
    expect(byKey['unit_b']!['target'], 'Lance');
  });

  test('wrapper object with a single array property yields its rows', () async {
    final path = await writeJson({
      'rows': [
        {'key': 'k1', 'source': 'a'},
        {'key': 'k2', 'source': 'b'},
      ],
    });

    final result = await reader.readFile(path, jsonSettings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.rows, hasLength(2));
    expect(result.value.rows.first['key'], 'k1');
  });

  test('unsupported JSON shape (map of scalars) returns a clear error '
      'instead of a silent empty import', () async {
    final path = await writeJson({'a': 1, 'b': 2});

    final result = await reader.readFile(path, jsonSettings());

    expect(result.isErr, isTrue,
        reason: 'An uninterpretable object root must be an error, not empty');
    expect(result.error.toString().toLowerCase(), contains('json'));
  });

  test('top-level array still works (unchanged)', () async {
    final path = await writeJson([
      {'key': 'k1', 'source': 'a'},
    ]);

    final result = await reader.readFile(path, jsonSettings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.rows, hasLength(1));
    expect(result.value.rows.first['key'], 'k1');
  });
}
