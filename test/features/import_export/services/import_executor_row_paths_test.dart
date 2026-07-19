import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/import_executor.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/file_service_impl.dart';
import 'package:twmt/services/history/history_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Per-row branch coverage for [ImportExecutor]: the missing-key error, the
/// "source text required" guard when creating a brand-new unit, the
/// pending-status path when no target text is imported, the useImported
/// overwrite of an existing version and progress reporting.
void main() {
  late Database db;
  late Directory tempDir;
  late ImportExecutor executor;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    tempDir = Directory.systemTemp.createTempSync('import_executor_rows_test');

    final versionRepo = TranslationVersionRepository();
    executor = ImportExecutor(
      ImportFileReader(FileServiceImpl()),
      TranslationUnitRepository(),
      versionRepo,
      HistoryServiceImpl(
        historyRepository: TranslationVersionHistoryRepository(),
        versionRepository: versionRepo,
      ),
      ProjectLanguageRepository(),
    );

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('languages', {
      'id': 'lang_fr',
      'code': 'fr',
      'name': 'French',
      'native_name': 'Francais',
      'is_active': 1,
    });
    await db.insert('projects', {
      'id': 'proj-1',
      'name': 'Project 1',
      'game_installation_id': 'game-1',
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('project_languages', {
      'id': 'pl-fr',
      'project_id': 'proj-1',
      'language_id': 'lang_fr',
      'status': 'pending',
      'progress_percent': 0,
      'created_at': now,
      'updated_at': now,
    });
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    await TestDatabase.close(db);
  });

  ImportSettings settings({Map<String, ImportColumn>? columnMapping}) =>
      ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        hasHeaderRow: true,
        columnMapping: columnMapping ??
            const {
              'key': ImportColumn.key,
              'source': ImportColumn.sourceText,
              'target': ImportColumn.targetText,
            },
      );

  Future<File> writeCsv(String content) async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString(content);
    return file;
  }

  Future<void> seedUnitAndVersion({String text = 'Salut'}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('translation_units', {
      'id': 'u1',
      'project_id': 'proj-1',
      'key': 'KEY_1',
      'source_text': 'Hello',
      'is_obsolete': 0,
      'created_at': now,
      'updated_at': now,
    });
    await db.insert('translation_versions', {
      'id': 'v1',
      'unit_id': 'u1',
      'project_language_id': 'pl-fr',
      'translated_text': text,
      'is_manually_edited': 0,
      'status': 'pending',
      'created_at': now,
      'updated_at': now,
    });
  }

  test('a row with an empty key is recorded as a "Missing key" error',
      () async {
    final file = await writeCsv('key,source,target\n,Hello,Bonjour\n');

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.errorCount, 1);
    expect(result.value.errors['0'], 'Missing key');
    expect(result.value.successCount, 0);
  });

  test('a brand-new key with empty source text errors with "Source text is '
      'required"', () async {
    final file = await writeCsv('key,source,target\nNEW_KEY,,Bonjour\n');

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.errorCount, 1);
    expect(result.value.errors['NEW_KEY'], contains('Source text is required'));
    // The orphan unit guard: no unit must be left behind for the failed row.
    final units = await db.query('translation_units',
        where: 'key = ?', whereArgs: ['NEW_KEY']);
    expect(units, isEmpty);
  });

  test('a new key with no target column creates a pending version', () async {
    final file = await writeCsv('key,source\nNEW_KEY,Hello\n');

    final result = await executor.executeImport(
      file.path,
      settings(columnMapping: const {
        'key': ImportColumn.key,
        'source': ImportColumn.sourceText,
      }),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.successCount, 1);

    final units = await db.query('translation_units',
        where: 'key = ?', whereArgs: ['NEW_KEY']);
    expect(units, hasLength(1));
    final versions = await db.query('translation_versions',
        where: 'unit_id = ?', whereArgs: [units.single['id']]);
    expect(versions, hasLength(1));
    expect(versions.single['status'], 'pending');
    final text = versions.single['translated_text'];
    expect(text == null || (text as String).isEmpty, isTrue);
  });

  test('useImported overwrites the existing version and reports progress',
      () async {
    await seedUnitAndVersion(text: 'Salut');
    final file = await writeCsv('key,source,target\nKEY_1,Hello,Bonjour\n');

    final progress = <List<int>>[];
    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(
        resolutions: {'KEY_1': ConflictResolution.useImported},
      ),
      onProgress: (current, total) => progress.add([current, total]),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.successCount, 1);
    expect(result.value.importedIds, isNotEmpty);
    expect(progress, [
      [1, 1],
    ]);

    final rows = await db.query(
      'translation_versions',
      where: 'id = ?',
      whereArgs: ['v1'],
    );
    expect(rows.single['translated_text'], 'Bonjour');
    expect(rows.single['status'], 'translated');
    expect(rows.single['is_manually_edited'], 1);
  });
}
