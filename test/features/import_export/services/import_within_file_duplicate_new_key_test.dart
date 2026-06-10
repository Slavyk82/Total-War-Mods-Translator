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

/// Regression test: when the import file contains the same key more than once
/// for a key that does NOT already exist in the database, row 1 created the
/// unit+version but row 2 was then treated as an existing-version conflict
/// requiring a per-key resolution that detectConflicts never produced (the unit
/// did not exist at preview time). _updateExistingVersion hit `resolution ==
/// null` and the row errored with "Unresolved conflict", silently dropping its
/// data. Within-file repeats of a new key must instead apply last-wins.
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
    tempDir = Directory.systemTemp.createTempSync('import_dup_new_key_test');

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
    // NOTE: no translation_units seeded — NEW_KEY does not exist in the DB.
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
    await TestDatabase.close(db);
  });

  ImportSettings settings() => const ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        hasHeaderRow: true,
        columnMapping: {
          'key': ImportColumn.key,
          'source': ImportColumn.sourceText,
          'target': ImportColumn.targetText,
        },
      );

  test(
      'a new key repeated within the file applies last-wins instead of '
      'erroring and dropping the second row', () async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString(
      'key,source,target\n'
      'NEW_KEY,Hello,Bonjour\n'
      'NEW_KEY,Hello,Salut\n',
    );

    // No per-key resolution: detectConflicts found nothing because the key did
    // not exist at preview time.
    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.errorCount, 0,
        reason: 'the repeated new-key row must not be a dropped error: '
            '${result.value.errors}');

    // Exactly one unit and one version exist, carrying the last row's value.
    final units = await db.query('translation_units',
        where: 'key = ?', whereArgs: ['NEW_KEY']);
    expect(units, hasLength(1));
    final versions = await db.query('translation_versions',
        where: 'unit_id = ?', whereArgs: [units.single['id']]);
    expect(versions, hasLength(1));
    expect(versions.single['translated_text'], 'Salut',
        reason: 'last write wins for an in-run duplicate');
  });
}
