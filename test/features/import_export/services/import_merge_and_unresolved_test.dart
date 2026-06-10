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

/// Regression tests for two ImportExecutor conflict-resolution findings:
///
/// F11: with ConflictResolution.merge, `existingVersion.translatedText ??
/// translatedText` kept an EMPTY existing translation ('' is non-null) and
/// discarded the imported text. Empty/whitespace-only existing text must be
/// treated as absent.
///
/// F5b: a conflicting row with NO resolution (key absent from the map and no
/// default) was silently counted in skippedCount, indistinguishable from an
/// explicit keepExisting. It must be surfaced to the user instead.
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
    tempDir = Directory.systemTemp.createTempSync('import_merge_test');

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

  Future<File> writeCsv() async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString('key,source,target\nKEY_1,Hello,Bonjour\n');
    return file;
  }

  Future<void> seedExistingVersion({required String? text}) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
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

  Future<String?> readTranslatedText() async {
    final rows = await db.query(
      'translation_versions',
      columns: ['translated_text'],
      where: 'id = ?',
      whereArgs: ['v1'],
    );
    return rows.single['translated_text'] as String?;
  }

  group('F11: merge with empty existing translation', () {
    test('merge takes the imported text when the existing text is empty',
        () async {
      await seedExistingVersion(text: '');
      final file = await writeCsv();

      final result = await executor.executeImport(
        file.path,
        settings(),
        const ConflictResolutions(
          resolutions: {'KEY_1': ConflictResolution.merge},
        ),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.successCount, 1);
      expect(
        await readTranslatedText(),
        'Bonjour',
        reason: 'an empty existing translation must not beat the import',
      );
    });

    test('merge takes the imported text when the existing text is whitespace',
        () async {
      await seedExistingVersion(text: '   ');
      final file = await writeCsv();

      final result = await executor.executeImport(
        file.path,
        settings(),
        const ConflictResolutions(
          resolutions: {'KEY_1': ConflictResolution.merge},
        ),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(await readTranslatedText(), 'Bonjour');
    });

    test('merge still keeps a non-empty existing translation', () async {
      await seedExistingVersion(text: 'Salut');
      final file = await writeCsv();

      final result = await executor.executeImport(
        file.path,
        settings(),
        const ConflictResolutions(
          resolutions: {'KEY_1': ConflictResolution.merge},
        ),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(await readTranslatedText(), 'Salut');
    });
  });

  group('F5b: unresolved conflict surfacing', () {
    test(
        'a conflicting row with no resolution is surfaced as an error, '
        'not silently counted as skipped', () async {
      await seedExistingVersion(text: 'Salut');
      final file = await writeCsv();

      final result = await executor.executeImport(
        file.path,
        settings(),
        const ConflictResolutions(), // no per-key entry, no default
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(
        result.value.errors,
        contains('KEY_1'),
        reason: 'the unresolved row must be reported with its key',
      );
      expect(result.value.errors['KEY_1'], contains('Unresolved conflict'));
      expect(result.value.errorCount, 1);
      expect(
        result.value.skippedCount,
        0,
        reason: 'unresolved must be distinguishable from explicit skip',
      );
      // The existing translation must be left untouched.
      expect(await readTranslatedText(), 'Salut');
    });

    test('an explicit keepExisting resolution still counts as skipped',
        () async {
      await seedExistingVersion(text: 'Salut');
      final file = await writeCsv();

      final result = await executor.executeImport(
        file.path,
        settings(),
        const ConflictResolutions(
          resolutions: {'KEY_1': ConflictResolution.keepExisting},
        ),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.skippedCount, 1);
      expect(result.value.errorCount, 0);
      expect(await readTranslatedText(), 'Salut');
    });
  });
}
