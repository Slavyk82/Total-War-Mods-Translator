import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/models/import_preview.dart';
import 'package:twmt/features/import_export/services/import_conflict_detector.dart';
import 'package:twmt/features/import_export/services/utils/import_file_reader.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/file_service_impl.dart';

import '../../../helpers/test_database.dart';

/// Happy-path and branch coverage for [ImportConflictDetector].
///
/// The existing regression suite (import_db_error_not_conflated_test) already
/// pins the Err/"not in project" paths; this file covers the cases where a
/// conflict IS produced (existing unit + version for the SAME language), the
/// `sourceTextDiffers` flag, the `changedBy` User/LLM mapping, the empty-key
/// short-circuit, the missing key-column short-circuit and the content-hash
/// integrity guard.
void main() {
  late Database db;
  late Directory tempDir;
  late ImportConflictDetector detector;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    tempDir = Directory.systemTemp.createTempSync('import_conflict_detect_test');

    detector = ImportConflictDetector(
      ImportFileReader(FileServiceImpl()),
      TranslationUnitRepository(),
      TranslationVersionRepository(),
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

  Future<File> writeCsv(String body) async {
    final file = File('${tempDir.path}/import.csv');
    await file.writeAsString('key,source,target\n$body');
    return file;
  }

  // Build a preview manually: the detector only reads filePath + contentHash
  // from it, re-reading the rows itself. contentHash defaults to null so the
  // integrity guard is skipped unless a test opts in.
  ImportPreview preview(String filePath, {String? contentHash}) => ImportPreview(
        filePath: filePath,
        headers: const ['key', 'source', 'target'],
        previewRows: const [],
        totalRows: 0,
        fileSize: 0,
        encoding: 'utf-8',
        contentHash: contentHash,
      );

  Future<void> seedVersion({
    String text = 'Salut',
    bool manual = false,
    String status = 'translated',
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db.insert('translation_versions', {
      'id': 'v1',
      'unit_id': 'u1',
      'project_language_id': 'pl-fr',
      'translated_text': text,
      'is_manually_edited': manual ? 1 : 0,
      'status': status,
      'created_at': now,
      'updated_at': now,
    });
  }

  test('produces a conflict when an existing version exists for the '
      'same language', () async {
    await seedVersion(text: 'Salut');
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final result = await detector.detectConflicts(preview(file.path), settings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value, hasLength(1));
    final conflict = result.value.single;
    expect(conflict.key, 'KEY_1');
    expect(conflict.existingData.sourceText, 'Hello');
    expect(conflict.existingData.translatedText, 'Salut');
    expect(conflict.existingData.status, 'translated');
    expect(conflict.existingData.changedBy, 'LLM'); // not manually edited
    expect(conflict.importedData.sourceText, 'Hello');
    expect(conflict.importedData.translatedText, 'Bonjour');
    expect(conflict.sourceTextDiffers, isFalse);
  });

  test('sourceTextDiffers is true when the imported source differs', () async {
    await seedVersion();
    final file = await writeCsv('KEY_1,Goodbye,Bonjour\n');

    final result = await detector.detectConflicts(preview(file.path), settings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.single.sourceTextDiffers, isTrue);
  });

  test('changedBy is User when the existing version was manually edited',
      () async {
    await seedVersion(manual: true);
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final result = await detector.detectConflicts(preview(file.path), settings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value.single.existingData.changedBy, 'User');
  });

  test('an existing unit with no version for the language is not a conflict',
      () async {
    // No version seeded — unit exists but has no translation yet.
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final result = await detector.detectConflicts(preview(file.path), settings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value, isEmpty);
  });

  test('a row with an empty key is skipped (no conflict)', () async {
    await seedVersion();
    // A conflicting row plus a blank-key row: only the first yields a conflict.
    final file = await writeCsv('KEY_1,Hello,Bonjour\n,Orphan,Ignored\n');

    final result = await detector.detectConflicts(preview(file.path), settings());

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value, hasLength(1));
  });

  test('no key column mapping short-circuits to no conflicts', () async {
    await seedVersion();
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final result = await detector.detectConflicts(
      preview(file.path),
      settings(columnMapping: const {
        'source': ImportColumn.sourceText,
        'target': ImportColumn.targetText,
      }),
    );

    expect(result.isOk, isTrue, reason: result.toString());
    expect(result.value, isEmpty);
  });

  test('a stale content hash aborts detection (integrity guard)', () async {
    await seedVersion();
    final file = await writeCsv('KEY_1,Hello,Bonjour\n');

    final result = await detector.detectConflicts(
      preview(file.path, contentHash: 'stale-hash-does-not-match'),
      settings(),
    );

    expect(result.isErr, isTrue, reason: result.toString());
    expect(result.error.message, contains('changed on disk since preview'));
  });

  test('a file read failure surfaces as a detection error', () async {
    final result = await detector.detectConflicts(
      preview('${tempDir.path}/missing.csv'),
      settings(),
    );

    expect(result.isErr, isTrue);
  });
}
