import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/services/import_executor.dart';
import 'package:twmt/features/import_export/services/import_preview_service.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/file_service_impl.dart';
import 'package:twmt/services/history/history_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Regression tests for the preview/execute TOCTOU gap in the import
/// workflow: previewImport, detectConflicts and executeImport each re-read
/// the file from disk. If the file changes between preview and execution,
/// the conflicts the user reviewed were computed on content A while the
/// import silently applies content B.
///
/// Guard: previewImport stores a sha256 content hash on ImportPreview;
/// executeImport re-verifies it (when provided) right before importing and
/// aborts with a clear, user-actionable error if the file changed.
void main() {
  late Database db;
  late Directory tempDir;
  late ImportExecutor executor;
  late ImportPreviewService previewService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    tempDir = Directory.systemTemp.createTempSync('import_integrity_test');

    final fileReader = ImportFileReader(FileServiceImpl());
    final versionRepo = TranslationVersionRepository();
    previewService = ImportPreviewService(fileReader);
    executor = ImportExecutor(
      fileReader,
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

  Future<File> writeCsv(String body) async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString('key,source,target\n$body');
    return file;
  }

  Future<int> countRows(String table) async {
    final rows = await db.query(table, columns: ['id']);
    return rows.length;
  }

  test(
      'file modified between preview and execute: import aborts with a clear '
      'error and imports nothing', () async {
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final previewResult =
        await previewService.previewImport(file.path, settings());
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());
    final staleHash = previewResult.value.contentHash;
    expect(staleHash, isNotNull,
        reason: 'previewImport must record a content hash');

    // The file changes on disk after the user reviewed the preview/conflicts.
    await file
        .writeAsString('key,source,target\nKEY_EVIL,Overwritten,Ecrase\n');

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
      expectedContentHash: staleHash,
    );

    expect(result.isErr, isTrue,
        reason: 'import must abort when the file changed since preview');
    expect(result.error.message, contains('changed on disk since preview'));
    expect(
      await countRows('translation_units'),
      0,
      reason: 'nothing must be imported from the changed file',
    );
    expect(await countRows('translation_versions'), 0);
  });

  test('unchanged file: content hash matches and the import succeeds',
      () async {
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final previewResult =
        await previewService.previewImport(file.path, settings());
    expect(previewResult.isOk, isTrue, reason: previewResult.toString());

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
      expectedContentHash: previewResult.value.contentHash,
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.successCount, 1);
    expect(await countRows('translation_units'), 1);
    expect(await countRows('translation_versions'), 1);
  });

  test('back-compat: executeImport without a content hash still imports',
      () async {
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final result = await executor.executeImport(
      file.path,
      settings(),
      const ConflictResolutions(),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.successCount, 1);
  });
}
