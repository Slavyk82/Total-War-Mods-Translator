import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../helpers/test_database.dart';

/// Unit tests for the *own* methods of [TranslationVersionRepository]
/// (CRUD + batch status mutations). Mixin methods (insertBatch/upsertBatch/
/// statistics) and the untranslated-filter / rescan paths are covered by their
/// own dedicated test files and are intentionally NOT re-tested here.
void main() {
  late Database db;
  late TranslationVersionRepository repo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repo = TranslationVersionRepository();
  });

  tearDown(() => TestDatabase.close(db));

  // Small fixed base timestamp keeps created_at <= updated_at well inside the
  // CHECK constraint regardless of the now-second the test runs at.
  const base = 1000;

  TranslationVersion makeVersion({
    String id = 'v1',
    String unitId = 'unit-1',
    String projectLanguageId = 'pl-1',
    String? translatedText,
    bool isManuallyEdited = false,
    TranslationVersionStatus status = TranslationVersionStatus.pending,
    TranslationSource translationSource = TranslationSource.unknown,
    String? validationIssues,
    int validationSchemaVersion = 0,
    int createdAt = base,
    int updatedAt = base,
  }) {
    return TranslationVersion(
      id: id,
      unitId: unitId,
      projectLanguageId: projectLanguageId,
      translatedText: translatedText,
      isManuallyEdited: isManuallyEdited,
      status: status,
      translationSource: translationSource,
      validationIssues: validationIssues,
      validationSchemaVersion: validationSchemaVersion,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  /// Insert a raw translation_versions row directly (bypassing the repo) so
  /// status/unit-key dependent methods can be set up precisely.
  Future<void> insertRawVersion({
    required String id,
    required String unitId,
    String projectLanguageId = 'pl-1',
    String? translatedText,
    String status = 'pending',
    String? validationIssues,
    int validationSchemaVersion = 0,
    int isManuallyEdited = 0,
    int createdAt = base,
    int updatedAt = base,
  }) async {
    await db.insert('translation_versions', {
      'id': id,
      'unit_id': unitId,
      'project_language_id': projectLanguageId,
      'translated_text': translatedText,
      'is_manually_edited': isManuallyEdited,
      'status': status,
      'validation_issues': validationIssues,
      'validation_schema_version': validationSchemaVersion,
      'created_at': createdAt,
      'updated_at': updatedAt,
    });
  }

  /// Insert a translation_units row (used by the *unit key* based methods).
  Future<void> insertRawUnit({
    required String id,
    String projectId = 'proj-1',
    required String key,
    String sourceText = 'src',
    int isObsolete = 0,
    int createdAt = base,
    int updatedAt = base,
  }) async {
    await db.insert('translation_units', {
      'id': id,
      'project_id': projectId,
      'key': key,
      'source_text': sourceText,
      'is_obsolete': isObsolete,
      'created_at': createdAt,
      'updated_at': updatedAt,
    });
  }

  group('insert', () {
    test('inserts a row and returns it', () async {
      final v = makeVersion(translatedText: 'hola');

      final result = await repo.insert(v);

      expect(result.isOk, isTrue);
      expect(result.value, equals(v));

      final rows = await db
          .query('translation_versions', where: 'id = ?', whereArgs: ['v1']);
      expect(rows.length, equals(1));
      expect(rows.first['translated_text'], equals('hola'));
      expect(rows.first['status'], equals('pending'));
    });

    test('fails when inserting a duplicate id (abort conflict)', () async {
      await repo.insert(makeVersion());

      final dup = makeVersion(unitId: 'unit-2', projectLanguageId: 'pl-2');
      final result = await repo.insert(dup);

      expect(result.isErr, isTrue);
    });
  });

  group('update', () {
    test('updates an existing row', () async {
      await repo.insert(makeVersion(status: TranslationVersionStatus.pending));

      final updated = makeVersion(
        translatedText: 'done',
        status: TranslationVersionStatus.translated,
        updatedAt: base + 5,
      );
      final result = await repo.update(updated);

      expect(result.isOk, isTrue);

      final row = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(row['status'], equals('translated'));
      expect(row['translated_text'], equals('done'));
    });

    test('returns error when row does not exist', () async {
      final result = await repo.update(makeVersion(id: 'missing'));

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('upsert', () {
    test('inserts when no row exists for (unit, project language)', () async {
      final v = makeVersion(translatedText: 'first');

      final result = await repo.upsert(v);

      expect(result.isOk, isTrue);
      final rows = await db.query('translation_versions');
      expect(rows.length, equals(1));
      expect(rows.first['translated_text'], equals('first'));
    });

    test('updates existing row preserving original created_at', () async {
      await repo.insert(makeVersion(
        translatedText: 'old',
        createdAt: base,
        updatedAt: base,
      ));

      // New entity with a different id + later created_at, same unit/lang.
      final replacement = makeVersion(
        id: 'v2',
        translatedText: 'new',
        status: TranslationVersionStatus.translated,
        createdAt: base + 100,
        updatedAt: base + 100,
      );
      final result = await repo.upsert(replacement);

      expect(result.isOk, isTrue);

      // Still one row, keyed by the ORIGINAL id, with the original created_at.
      final rows = await db.query('translation_versions');
      expect(rows.length, equals(1));
      expect(rows.first['id'], equals('v1'));
      expect(rows.first['translated_text'], equals('new'));
      expect(rows.first['created_at'], equals(base),
          reason: 'created_at must be preserved on upsert-update');
    });
  });

  group('delete', () {
    test('deletes an existing row', () async {
      await repo.insert(makeVersion());

      final result = await repo.delete('v1');

      expect(result.isOk, isTrue);
      final rows = await db.query('translation_versions');
      expect(rows, isEmpty);
    });

    test('returns error when row does not exist', () async {
      final result = await repo.delete('missing');

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('getById', () {
    test('returns the row when found', () async {
      await repo.insert(makeVersion(translatedText: 'x'));

      final result = await repo.getById('v1');

      expect(result.isOk, isTrue);
      expect(result.value.id, equals('v1'));
      expect(result.value.translatedText, equals('x'));
    });

    test('returns error when not found', () async {
      final result = await repo.getById('nope');

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('getByUnit', () {
    test('returns all versions for the unit ordered by created_at DESC',
        () async {
      await insertRawVersion(
          id: 'a', unitId: 'unit-1', projectLanguageId: 'pl-1', createdAt: base, updatedAt: base);
      await insertRawVersion(
          id: 'b', unitId: 'unit-1', projectLanguageId: 'pl-2', createdAt: base + 50, updatedAt: base + 50);
      await insertRawVersion(
          id: 'c', unitId: 'unit-OTHER', projectLanguageId: 'pl-1');

      final result = await repo.getByUnit('unit-1');

      expect(result.isOk, isTrue);
      final ids = result.value.map((v) => v.id).toList();
      expect(ids, equals(['b', 'a']),
          reason: 'newest created_at first');
    });

    test('returns empty list for an unknown unit', () async {
      final result = await repo.getByUnit('unit-unknown');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('getByStatus', () {
    test('returns only rows matching the status', () async {
      await insertRawVersion(id: 'p1', unitId: 'u1', status: 'pending');
      await insertRawVersion(id: 't1', unitId: 'u2', status: 'translated');
      await insertRawVersion(id: 't2', unitId: 'u3', status: 'translated');

      final result = await repo.getByStatus('translated');

      expect(result.isOk, isTrue);
      expect(result.value.map((v) => v.id).toSet(), equals({'t1', 't2'}));
    });

    test('returns empty list when no rows match', () async {
      await insertRawVersion(id: 'p1', unitId: 'u1', status: 'pending');

      final result = await repo.getByStatus('needs_review');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('getTranslatedUnitIds', () {
    test('returns unit ids with non-empty translated_text for the language',
        () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', projectLanguageId: 'pl-1', translatedText: 'hi');
      await insertRawVersion(
          id: 'v2', unitId: 'u2', projectLanguageId: 'pl-1', translatedText: '');
      await insertRawVersion(
          id: 'v3', unitId: 'u3', projectLanguageId: 'pl-1', translatedText: null);
      await insertRawVersion(
          id: 'v4', unitId: 'u4', projectLanguageId: 'pl-OTHER', translatedText: 'other');

      final result = await repo.getTranslatedUnitIds(
        unitIds: ['u1', 'u2', 'u3', 'u4'],
        projectLanguageId: 'pl-1',
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals({'u1'}));
    });

    test('returns empty set when unitIds is empty', () async {
      final result = await repo.getTranslatedUnitIds(
        unitIds: const [],
        projectLanguageId: 'pl-1',
      );

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('clearBatch', () {
    test('clears translated_text and resets status to pending', () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'done', status: 'translated');
      await insertRawVersion(
          id: 'v2', unitId: 'u2', translatedText: 'done2', status: 'translated');

      final result = await repo.clearBatch(['v1', 'v2']);

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final rows = await db.query('translation_versions', orderBy: 'id');
      expect(rows[0]['translated_text'], equals(''));
      expect(rows[0]['status'], equals('pending'));
      expect(rows[1]['translated_text'], equals(''));
      expect(rows[1]['status'], equals('pending'));
    });

    test('returns 0 for an empty id list without touching rows', () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'done', status: 'translated');

      final result = await repo.clearBatch([]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));

      final row = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(row['status'], equals('translated'),
          reason: 'untouched on empty input');
    });
  });

  group('acceptBatch', () {
    test('sets status to translated and clears validation_issues', () async {
      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          translatedText: 'done',
          status: 'needs_review',
          validationIssues: '[some-issue]');

      final result = await repo.acceptBatch(['v1']);

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final row = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(row['status'], equals('translated'));
      expect(row['validation_issues'], isNull);
    });

    test('returns 0 for empty input', () async {
      final result = await repo.acceptBatch([]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });

    test('accepts a >50 batch via the disable-triggers path', () async {
      const count = 69;
      final ids = <String>[];
      for (var i = 0; i < count; i++) {
        final id = 'bv$i';
        ids.add(id);
        await insertRawVersion(
          id: id,
          unitId: 'bu$i',
          translatedText: 'done $i',
          status: 'needs_review',
          validationIssues: '[some-issue]',
        );
      }

      final result = await repo.acceptBatch(ids);

      expect(result.isOk, isTrue, reason: 'error: ${result.isErr ? result.error : ''}');
      expect(result.value, equals(count));

      final rows = await db.query('translation_versions');
      for (final row in rows) {
        expect(row['status'], equals('translated'),
            reason: 'row ${row['id']} should be accepted');
        expect(row['validation_issues'], isNull);
      }
    });
  });

  group('rejectBatch', () {
    test('nulls translated_text, resets status, clears validation_issues',
        () async {
      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          translatedText: 'bad',
          status: 'needs_review',
          validationIssues: '[issue]');

      final result = await repo.rejectBatch(['v1']);

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final row = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(row['translated_text'], isNull);
      expect(row['status'], equals('pending'));
      expect(row['validation_issues'], isNull);
    });

    test('returns 0 for empty input', () async {
      final result = await repo.rejectBatch([]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('updateValidationBatch', () {
    test('updates status, validation_issues and schema version per row',
        () async {
      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          translatedText: 'txt',
          status: 'translated',
          validationSchemaVersion: 0);

      final result = await repo.updateValidationBatch([
        (
          versionId: 'v1',
          status: 'needs_review',
          validationIssues: '[issue]',
          schemaVersion: 7,
        ),
      ]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final row = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(row['status'], equals('needs_review'));
      expect(row['validation_issues'], equals('[issue]'));
      expect(row['validation_schema_version'], equals(7));
    });

    test('returns 0 for empty input', () async {
      final result = await repo.updateValidationBatch([]);

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('countLegacyValidationRows', () {
    test('counts below-current rows that have a non-empty translation',
        () async {
      // Legacy + translated -> counted.
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'txt', validationSchemaVersion: 0);
      // Legacy but empty translation -> NOT counted.
      await insertRawVersion(
          id: 'v2', unitId: 'u2', translatedText: '', validationSchemaVersion: 0);
      // Legacy but null translation -> NOT counted.
      await insertRawVersion(
          id: 'v3', unitId: 'u3', translatedText: null, validationSchemaVersion: 0);

      final result = await repo.countLegacyValidationRows();

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));
    });

    test('returns 0 when there are no rows', () async {
      final result = await repo.countLegacyValidationRows();

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('countMigratedValidationRows', () {
    test('counts rows at or above the current schema version', () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'a', validationSchemaVersion: 999);
      await insertRawVersion(
          id: 'v2', unitId: 'u2', translatedText: 'b', validationSchemaVersion: 0);

      final result = await repo.countMigratedValidationRows();

      expect(result.isOk, isTrue);
      // 999 is well above kCurrentValidationSchemaVersion -> exactly 1 migrated.
      expect(result.value, equals(1));
    });

    test('returns 0 when only legacy rows exist', () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'a', validationSchemaVersion: 0);

      final result = await repo.countMigratedValidationRows();

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('normalizeStatusEncoding', () {
    test('is a no-op (returns 0) when no camelCase status rows exist',
        () async {
      // CHECK(status IN (...)) forbids inserting the stale 'needsReview'
      // value through normal paths, so the seeded rows use canonical values.
      await insertRawVersion(id: 'v1', unitId: 'u1', status: 'needs_review');
      await insertRawVersion(id: 'v2', unitId: 'u2', status: 'translated');

      final result = await repo.normalizeStatusEncoding();

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));

      // Canonical rows are untouched.
      final row = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(row['status'], equals('needs_review'));
    });

    test('repairs rows stored as camelCase needsReview', () async {
      // The CHECK constraint normally blocks the camelCase value; drop it for
      // this row by recreating the table without the status CHECK so we can
      // exercise the repair UPDATE itself.
      await db.execute('DROP TABLE translation_versions');
      await db.execute('''
        CREATE TABLE translation_versions (
          id TEXT PRIMARY KEY,
          unit_id TEXT NOT NULL,
          project_language_id TEXT NOT NULL,
          translated_text TEXT,
          is_manually_edited INTEGER NOT NULL DEFAULT 0,
          status TEXT NOT NULL DEFAULT 'pending',
          translation_source TEXT DEFAULT 'unknown',
          validation_issues TEXT,
          validation_schema_version INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
      await insertRawVersion(id: 'v1', unitId: 'u1', status: 'needsReview');
      await insertRawVersion(id: 'v2', unitId: 'u2', status: 'pending');

      final result = await repo.normalizeStatusEncoding();

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final repaired = (await db.query('translation_versions',
              where: 'id = ?', whereArgs: ['v1']))
          .first;
      expect(repaired['status'], equals('needs_review'));
    });
  });

  group('resetStatusForUnitKeys', () {
    test('sets status to pending for versions of the given unit keys', () async {
      await insertRawUnit(id: 'u1', projectId: 'proj-1', key: 'key-1');
      await insertRawUnit(id: 'u2', projectId: 'proj-1', key: 'key-2');
      await insertRawUnit(id: 'u3', projectId: 'proj-1', key: 'key-3');
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'a', status: 'translated');
      await insertRawVersion(
          id: 'v2', unitId: 'u2', translatedText: 'b', status: 'needs_review');
      await insertRawVersion(
          id: 'v3', unitId: 'u3', translatedText: 'c', status: 'translated');

      final result = await repo.resetStatusForUnitKeys(
        projectId: 'proj-1',
        unitKeys: ['key-1', 'key-2'],
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(2));

      final rows = await db.query('translation_versions', orderBy: 'id');
      expect(rows[0]['status'], equals('pending'));
      expect(rows[0]['translated_text'], equals('a'),
          reason: 'translated_text must be preserved');
      expect(rows[1]['status'], equals('pending'));
      expect(rows[2]['status'], equals('translated'),
          reason: 'key-3 not in the list -> untouched');
    });

    test('returns 0 for empty unit key list', () async {
      final result = await repo.resetStatusForUnitKeys(
        projectId: 'proj-1',
        unitKeys: const [],
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('setNeedsReviewForUnitKeys', () {
    test('sets status to needs_review for versions of the given unit keys',
        () async {
      await insertRawUnit(id: 'u1', projectId: 'proj-1', key: 'key-1');
      await insertRawUnit(id: 'u2', projectId: 'proj-1', key: 'key-2');
      await insertRawVersion(
          id: 'v1', unitId: 'u1', translatedText: 'a', status: 'translated');
      await insertRawVersion(
          id: 'v2', unitId: 'u2', translatedText: 'b', status: 'translated');

      final result = await repo.setNeedsReviewForUnitKeys(
        projectId: 'proj-1',
        unitKeys: ['key-1'],
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(1));

      final rows = await db.query('translation_versions', orderBy: 'id');
      expect(rows[0]['status'], equals('needs_review'));
      expect(rows[0]['translated_text'], equals('a'),
          reason: 'translated_text must be preserved');
      expect(rows[1]['status'], equals('translated'),
          reason: 'key-2 not in the list -> untouched');
    });

    test('returns 0 for empty unit key list', () async {
      final result = await repo.setNeedsReviewForUnitKeys(
        projectId: 'proj-1',
        unitKeys: const [],
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(0));
    });
  });

  group('getNeedsReviewIds', () {
    test('returns ids of needs_review rows for the project language', () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', projectLanguageId: 'pl-1', status: 'needs_review');
      await insertRawVersion(
          id: 'v2', unitId: 'u2', projectLanguageId: 'pl-1', status: 'translated');
      await insertRawVersion(
          id: 'v3', unitId: 'u3', projectLanguageId: 'pl-OTHER', status: 'needs_review');

      final result = await repo.getNeedsReviewIds(projectLanguageId: 'pl-1');

      expect(result.isOk, isTrue);
      expect(result.value.toSet(), equals({'v1'}));
    });

    test('returns empty list when no needs_review rows exist for the language',
        () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', projectLanguageId: 'pl-1', status: 'translated');

      final result = await repo.getNeedsReviewIds(projectLanguageId: 'pl-1');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });
}
