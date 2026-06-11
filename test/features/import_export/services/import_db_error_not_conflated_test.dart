import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/import_conflict_detector.dart';
import 'package:twmt/features/import_export/services/import_executor.dart';
import 'package:twmt/features/import_export/services/import_preview_service.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/file_service_impl.dart';
import 'package:twmt/services/history/history_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression tests for F6: a REAL database failure during the
/// "does a version already exist for this unit + language?" lookup used to be
/// indistinguishable from "no version found" (the repository returned Err for
/// both). The executor then wrongly took the "create new version" path
/// (risking a UNIQUE(unit_id, project_language_id) violation or a silent
/// duplicate-ish insert), and the conflict detector silently reported
/// "no conflict".
///
/// The fix introduces `findByUnitAndProjectLanguage` (Ok(null) == genuinely
/// absent, Err == real DB failure) and propagates real failures as a row
/// error (executor) / detection failure (detector).
///
/// The same conflation existed for the project-language lookup at the start
/// of import preview/execution: `getByProjectAndLanguage` returned Err both
/// for "no such project language" and for a real DB failure. Those paths now
/// use `findByProjectAndLanguage` with the same Ok(null)/Err split, covered
/// by the "project-language lookup" tests below.
void main() {
  late Database db;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    tempDir = Directory.systemTemp.createTempSync('import_db_error_test');

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
    await db.insert('translation_units', {
      'id': 'u1',
      'project_id': 'proj-1',
      'key': 'KEY_1',
      'source_text': 'Hello',
      'is_obsolete': 0,
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

  ImportSettings settings({String targetLanguageId = 'lang_fr'}) =>
      ImportSettings(
        format: ImportFormat.csv,
        projectId: 'proj-1',
        targetLanguageId: targetLanguageId,
        hasHeaderRow: true,
        columnMapping: {
          'key': ImportColumn.key,
          'source': ImportColumn.sourceText,
          'target': ImportColumn.targetText,
        },
      );

  Future<File> writeCsv() async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString('key,source,target\nKEY_1,Hello,Bonjour\n');
    return file;
  }

  ImportExecutor buildExecutor(
    TranslationVersionRepository versionRepo, {
    ProjectLanguageRepository? projectLanguageRepo,
  }) {
    final unitRepo = TranslationUnitRepository();
    final history = HistoryServiceImpl(
      historyRepository: TranslationVersionHistoryRepository(),
      versionRepository: versionRepo,
    );
    return ImportExecutor(
      ImportFileReader(FileServiceImpl()),
      unitRepo,
      versionRepo,
      history,
      projectLanguageRepo ?? ProjectLanguageRepository(),
    );
  }

  test('absent version still imports as a new version (not-found path intact)',
      () async {
    final file = await writeCsv();
    final executor = buildExecutor(TranslationVersionRepository());

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.successCount, 1);
    expect(result.value.errorCount, 0);

    final rows = await db.query(
      'translation_versions',
      where: 'unit_id = ? AND project_language_id = ?',
      whereArgs: ['u1', 'pl-fr'],
    );
    expect(rows.length, 1);
    expect(rows.first['translated_text'], 'Bonjour');
  });

  test(
      'real DB failure during version lookup is recorded as a row error, '
      'not treated as "no version" and inserted', () async {
    final file = await writeCsv();
    final executor = buildExecutor(_FailingLookupVersionRepository());

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(
      result.value.errorCount,
      1,
      reason: 'a real DB lookup failure must surface as a row error',
    );
    expect(result.value.errors, contains('KEY_1'));
    expect(result.value.successCount, 0);

    // The buggy behavior inserted a "new" version on lookup failure.
    final rows = await db.query(
      'translation_versions',
      where: 'unit_id = ? AND project_language_id = ?',
      whereArgs: ['u1', 'pl-fr'],
    );
    expect(
      rows,
      isEmpty,
      reason: 'no version must be inserted when the lookup failed',
    );
  });

  test(
      'detectConflicts surfaces a real DB failure instead of silently '
      'reporting "no conflict"', () async {
    final file = await writeCsv();

    // Seed an existing version so that, were the DB healthy, this row WOULD
    // be a conflict. The failing lookup must not be reported as "no conflict".
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('translation_versions', {
      'id': 'v1',
      'unit_id': 'u1',
      'project_language_id': 'pl-fr',
      'translated_text': 'Salut',
      'is_manually_edited': 0,
      'status': 'translated',
      'created_at': now,
      'updated_at': now,
    });

    final reader = ImportFileReader(FileServiceImpl());
    final previewResult = await ImportPreviewService(reader)
        .previewImport(file.path, settings());
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());

    final detector = ImportConflictDetector(
      reader,
      TranslationUnitRepository(),
      _FailingLookupVersionRepository(),
      ProjectLanguageRepository(),
    );

    final result =
        await detector.detectConflicts(previewResult.value, settings());

    expect(
      result.isErr,
      isTrue,
      reason: 'a real DB failure must fail conflict detection, got: $result',
    );
  });

  test(
      'detectConflicts surfaces a real DB failure during the project-language '
      'lookup instead of silently reporting "no conflicts"', () async {
    final file = await writeCsv();

    final reader = ImportFileReader(FileServiceImpl());
    final previewResult = await ImportPreviewService(reader)
        .previewImport(file.path, settings());
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());

    final detector = ImportConflictDetector(
      reader,
      TranslationUnitRepository(),
      TranslationVersionRepository(),
      _FailingProjectLanguageRepository(),
    );

    final result =
        await detector.detectConflicts(previewResult.value, settings());

    expect(
      result.isErr,
      isTrue,
      reason: 'a real DB failure during the project-language lookup must '
          'fail conflict detection, got: $result',
    );
  });

  test(
      'detectConflicts reports no conflicts when the target language is '
      'genuinely not part of the project', () async {
    final file = await writeCsv();
    final notInProject = settings(targetLanguageId: 'lang_de');

    final reader = ImportFileReader(FileServiceImpl());
    final previewResult = await ImportPreviewService(reader)
        .previewImport(file.path, notInProject);
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());

    final detector = ImportConflictDetector(
      reader,
      TranslationUnitRepository(),
      TranslationVersionRepository(),
      ProjectLanguageRepository(),
    );

    final result =
        await detector.detectConflicts(previewResult.value, notInProject);

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value, isEmpty);
  });

  test(
      'executeImport surfaces a real DB failure during the project-language '
      'lookup instead of mislabeling it "language not in project"', () async {
    final file = await writeCsv();
    final executor = buildExecutor(
      TranslationVersionRepository(),
      projectLanguageRepo: _FailingProjectLanguageRepository(),
    );

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(
      result.isErr,
      isTrue,
      reason: 'a real DB failure must fail the import, got: $result',
    );
    expect(
      result.error.message,
      isNot(contains('not part of this project')),
      reason: 'a real DB failure must not be reported as a missing language',
    );
  });

  test('executeImport rejects a target language that is not in the project',
      () async {
    final file = await writeCsv();
    final executor = buildExecutor(TranslationVersionRepository());

    final result = await executor.executeImport(
      file.path,
      settings(targetLanguageId: 'lang_de'),
      const ConflictResolutions(),
    );

    expect(result.isErr, isTrue, reason: result.toString());
    expect(result.error.message, contains('not part of this project'));
  });
}

/// Fake that simulates a real database failure (e.g. locked/corrupt DB) on
/// the version-by-unit-and-language lookup while every other operation hits
/// the real in-memory database.
class _FailingLookupVersionRepository extends TranslationVersionRepository {
  static const _failure = TWMTDatabaseException('database is locked');

  @override
  Future<Result<TranslationVersion, TWMTDatabaseException>>
      getByUnitAndProjectLanguage({
    required String unitId,
    required String projectLanguageId,
  }) async {
    return const Err(_failure);
  }

  // Covers the find-variant introduced by the F6 fix.
  @override
  Future<Result<TranslationVersion?, TWMTDatabaseException>>
      findByUnitAndProjectLanguage({
    required String unitId,
    required String projectLanguageId,
  }) async {
    return const Err(_failure);
  }
}

/// Fake that simulates a real database failure (e.g. locked/corrupt DB) on
/// the project-language lookup while every other operation hits the real
/// in-memory database.
class _FailingProjectLanguageRepository extends ProjectLanguageRepository {
  static const _failure = TWMTDatabaseException('database is locked');

  @override
  Future<Result<ProjectLanguage, TWMTDatabaseException>>
      getByProjectAndLanguage(String projectId, String languageId) async {
    return const Err(_failure);
  }

  @override
  Future<Result<ProjectLanguage?, TWMTDatabaseException>>
      findByProjectAndLanguage(String projectId, String languageId) async {
    return const Err(_failure);
  }
}
