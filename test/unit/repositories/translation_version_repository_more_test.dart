import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../helpers/test_database.dart';

/// Additional coverage for [TranslationVersionRepository] methods/branches NOT
/// exercised by the sibling test files:
///
/// - `getAll`
/// - `getByProjectLanguage`
/// - `getByUnitAndProjectLanguage` (found + not-found Err)
/// - `findByUnitAndProjectLanguage` (Ok(entity) + Ok(null))
/// - `clearBatch` >50-row path (triggers DROPped/recreated, manual FTS + cache
///   + project-language-progress maintenance) — the sibling methods test only
///   covers the small-batch path that keeps triggers live.
/// - `reanalyzeAllStatuses` (fixedToPending / fixedToTranslated / no-op rows)
/// - `countInconsistentStatuses`
/// - `getNeedsReviewRows` (incl. obsolete-unit filtering)
///
/// Rows are seeded with raw `db.insert` maps so we can set statuses the Dart
/// enum cannot produce and keep precise control over translated_text/obsolete.
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

  // Fixed base timestamp keeps created_at <= updated_at well inside the CHECK
  // constraint regardless of the wall-clock second the test runs at.
  const base = 1000;

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

  Future<void> insertRawCache({
    required String id,
    required String versionId,
    required String unitId,
    String projectId = 'proj-1',
    String projectLanguageId = 'pl-1',
    String languageCode = 'es',
    String key = 'k',
    String sourceText = 'src',
    String? translatedText,
    String status = 'translated',
  }) async {
    await db.insert('translation_view_cache', {
      'id': id,
      'project_id': projectId,
      'project_language_id': projectLanguageId,
      'language_code': languageCode,
      'unit_id': unitId,
      'version_id': versionId,
      'key': key,
      'source_text': sourceText,
      'translated_text': translatedText,
      'status': status,
      'is_manually_edited': 0,
      'is_obsolete': 0,
      'unit_created_at': base,
      'unit_updated_at': base,
      'version_updated_at': base,
    });
  }

  group('getAll', () {
    test('returns empty list when there are no rows', () async {
      final result = await repo.getAll();

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });

    test('returns all rows ordered by created_at DESC', () async {
      await insertRawVersion(
          id: 'old', unitId: 'u1', createdAt: base, updatedAt: base);
      await insertRawVersion(
          id: 'new', unitId: 'u2', createdAt: base + 100, updatedAt: base + 100);
      await insertRawVersion(
          id: 'mid', unitId: 'u3', createdAt: base + 50, updatedAt: base + 50);

      final result = await repo.getAll();

      expect(result.isOk, isTrue);
      expect(result.value.map((v) => v.id).toList(),
          equals(['new', 'mid', 'old']),
          reason: 'newest created_at first');
    });
  });

  group('getByProjectLanguage', () {
    test('returns only rows matching the project language, DESC order',
        () async {
      await insertRawVersion(
          id: 'a',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          createdAt: base,
          updatedAt: base);
      await insertRawVersion(
          id: 'b',
          unitId: 'u2',
          projectLanguageId: 'pl-1',
          createdAt: base + 10,
          updatedAt: base + 10);
      await insertRawVersion(
          id: 'c', unitId: 'u3', projectLanguageId: 'pl-OTHER');

      final result = await repo.getByProjectLanguage('pl-1');

      expect(result.isOk, isTrue);
      expect(result.value.map((v) => v.id).toList(), equals(['b', 'a']),
          reason: 'only pl-1 rows, newest first');
    });

    test('returns empty list when no rows match the language', () async {
      await insertRawVersion(
          id: 'a', unitId: 'u1', projectLanguageId: 'pl-1');

      final result = await repo.getByProjectLanguage('pl-MISSING');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });

  group('getByUnitAndProjectLanguage', () {
    test('returns the matching version', () async {
      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'hola');
      // Decoys that match only one of the two predicates.
      await insertRawVersion(
          id: 'v2', unitId: 'u1', projectLanguageId: 'pl-OTHER');
      await insertRawVersion(
          id: 'v3', unitId: 'u-OTHER', projectLanguageId: 'pl-1');

      final result = await repo.getByUnitAndProjectLanguage(
        unitId: 'u1',
        projectLanguageId: 'pl-1',
      );

      expect(result.isOk, isTrue);
      expect(result.value.id, equals('v1'));
      expect(result.value.translatedText, equals('hola'));
    });

    test('returns an error when no row matches both unit and language',
        () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', projectLanguageId: 'pl-OTHER');

      final result = await repo.getByUnitAndProjectLanguage(
        unitId: 'u1',
        projectLanguageId: 'pl-1',
      );

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('not found'));
    });
  });

  group('findByUnitAndProjectLanguage', () {
    test('returns Ok(entity) when a row matches', () async {
      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'bonjour');

      final result = await repo.findByUnitAndProjectLanguage(
        unitId: 'u1',
        projectLanguageId: 'pl-1',
      );

      expect(result.isOk, isTrue);
      expect(result.value, isNotNull);
      expect(result.value!.id, equals('v1'));
    });

    test('returns Ok(null) (not an error) when no row matches', () async {
      await insertRawVersion(
          id: 'v1', unitId: 'u1', projectLanguageId: 'pl-OTHER');

      final result = await repo.findByUnitAndProjectLanguage(
        unitId: 'u1',
        projectLanguageId: 'pl-1',
      );

      expect(result.isOk, isTrue,
          reason: 'a miss is Ok(null), never an Err');
      expect(result.value, isNull);
    });
  });

  group('clearBatch (large batch >50 — trigger-disabled path)', () {
    test(
        'clears all rows, recreates triggers, and manually maintains '
        'FTS/cache/progress', () async {
      // 60 rows (> the 50 threshold) so the disableTriggers branch runs.
      const n = 60;
      for (var i = 0; i < n; i++) {
        final id = 'v${i.toString().padLeft(3, '0')}';
        await insertRawVersion(
          id: id,
          unitId: 'u$i',
          projectLanguageId: 'pl-1',
          translatedText: 'done $i',
          status: 'translated',
        );
        // One cache row per version so the manual cache-update branch has
        // something to touch.
        await insertRawCache(
          id: 'c$i',
          versionId: id,
          unitId: 'u$i',
          translatedText: 'done $i',
          status: 'translated',
        );
      }

      final ids = [for (var i = 0; i < n; i++) 'v${i.toString().padLeft(3, '0')}'];

      final phases = <String>{};
      final result = await repo.clearBatch(
        ids,
        onProgress: (processed, total, phase) => phases.add(phase),
      );

      expect(result.isOk, isTrue);
      expect(result.value, equals(n));

      // Every version is cleared + reset.
      final cleared = await db.query('translation_versions',
          where: "translated_text = '' AND status = 'pending'");
      expect(cleared.length, equals(n));

      // Manual FTS maintenance branch removed all FTS rows for these versions.
      final ftsRows = await db.rawQuery(
          'SELECT COUNT(*) AS c FROM translation_versions_fts');
      expect(ftsRows.first['c'], equals(0));

      // Manual cache-update branch reset the cached rows in place.
      final cacheRows = await db.query('translation_view_cache',
          where: "translated_text = '' AND status = 'pending'");
      expect(cacheRows.length, equals(n),
          reason: 'cache rows updated by the manual branch');

      // The trigger-disabled path emits the dedicated progress phases.
      expect(phases, contains('Preparing batch operation...'));
      expect(phases, contains('Updating search index...'));
      expect(phases, contains('Updating cache...'));
      expect(phases, contains('Updating statistics...'));

      // Triggers were recreated in the `finally` block (assert one is live).
      final liveTriggers = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'trigger' "
        "AND name = 'trg_update_cache_on_version_change'",
      );
      expect(liveTriggers.length, equals(1),
          reason: 'dropped triggers must be recreated after the batch');
    });
  });

  group('reanalyzeAllStatuses', () {
    test(
        'fixes empty-text non-pending rows to pending and text-bearing '
        'pending/translating rows to translated', () async {
      // -> fixedToPending: empty text but status 'needs_review'.
      await insertRawVersion(
          id: 'p1', unitId: 'u1', translatedText: '', status: 'needs_review');
      // -> fixedToPending: null text but status 'translated'.
      await insertRawVersion(
          id: 'p2', unitId: 'u2', translatedText: null, status: 'translated');
      // -> fixedToTranslated: has text but status 'pending', not manual.
      await insertRawVersion(
          id: 't1', unitId: 'u3', translatedText: 'hi', status: 'pending');
      // -> fixedToTranslated: has text but status 'translating', not manual.
      await insertRawVersion(
          id: 't2', unitId: 'u4', translatedText: 'yo', status: 'translating');
      // Untouched: 'translating' WITHOUT text is a valid in-progress state.
      await insertRawVersion(
          id: 'skip1', unitId: 'u5', translatedText: null, status: 'translating');
      // Untouched: has text + pending BUT manually edited -> excluded.
      await insertRawVersion(
          id: 'skip2',
          unitId: 'u6',
          translatedText: 'manual',
          status: 'pending',
          isManuallyEdited: 1);

      final result = await repo.reanalyzeAllStatuses();

      expect(result.isOk, isTrue);
      final r = result.value;
      expect(r.fixedToPending, equals(2));
      expect(r.fixedToTranslated, equals(2));
      expect(r.total, equals(6));

      Future<String?> statusOf(String id) async => (await db.query(
              'translation_versions',
              columns: ['status'],
              where: 'id = ?',
              whereArgs: [id]))
          .first['status'] as String?;

      expect(await statusOf('p1'), equals('pending'));
      expect(await statusOf('p2'), equals('pending'));
      expect(await statusOf('t1'), equals('translated'));
      expect(await statusOf('t2'), equals('translated'));
      expect(await statusOf('skip1'), equals('translating'),
          reason: 'in-progress translating row untouched');
      expect(await statusOf('skip2'), equals('pending'),
          reason: 'manually edited row untouched');
    });

    test('returns zero counts with total when nothing is inconsistent',
        () async {
      await insertRawVersion(
          id: 'ok1', unitId: 'u1', translatedText: 'fine', status: 'translated');
      await insertRawVersion(
          id: 'ok2', unitId: 'u2', translatedText: null, status: 'pending');

      final result = await repo.reanalyzeAllStatuses();

      expect(result.isOk, isTrue);
      expect(result.value.fixedToPending, equals(0));
      expect(result.value.fixedToTranslated, equals(0));
      expect(result.value.total, equals(2));
    });
  });

  group('countInconsistentStatuses', () {
    test('counts pending-with-text and non-pending-without-text separately',
        () async {
      // pendingWithText: text + pending/translating, not manual.
      await insertRawVersion(
          id: 'a', unitId: 'u1', translatedText: 'x', status: 'pending');
      await insertRawVersion(
          id: 'b', unitId: 'u2', translatedText: 'y', status: 'translating');
      // Excluded from pendingWithText: manually edited.
      await insertRawVersion(
          id: 'c',
          unitId: 'u3',
          translatedText: 'z',
          status: 'pending',
          isManuallyEdited: 1);

      // nonPendingWithoutText: empty/null text + non-pending status.
      await insertRawVersion(
          id: 'd', unitId: 'u4', translatedText: '', status: 'translated');
      await insertRawVersion(
          id: 'e', unitId: 'u5', translatedText: null, status: 'needs_review');

      // Consistent rows (counted in neither bucket).
      await insertRawVersion(
          id: 'f', unitId: 'u6', translatedText: 'ok', status: 'translated');

      final result = await repo.countInconsistentStatuses();

      expect(result.isOk, isTrue);
      expect(result.value.pendingWithText, equals(2));
      expect(result.value.nonPendingWithoutText, equals(2));
    });

    test('returns zeros when all rows are consistent', () async {
      await insertRawVersion(
          id: 'a', unitId: 'u1', translatedText: 'ok', status: 'translated');
      await insertRawVersion(
          id: 'b', unitId: 'u2', translatedText: null, status: 'pending');

      final result = await repo.countInconsistentStatuses();

      expect(result.isOk, isTrue);
      expect(result.value.pendingWithText, equals(0));
      expect(result.value.nonPendingWithoutText, equals(0));
    });
  });

  group('getNeedsReviewRows', () {
    test(
        'returns display rows for needs_review versions of non-obsolete units, '
        'ordered by key', () async {
      await insertRawUnit(
          id: 'u1', key: 'zeta', sourceText: 'Zeta source', isObsolete: 0);
      await insertRawUnit(
          id: 'u2', key: 'alpha', sourceText: 'Alpha source', isObsolete: 0);
      // Obsolete unit -> filtered out even though its version needs review.
      await insertRawUnit(
          id: 'u3', key: 'beta', sourceText: 'Beta source', isObsolete: 1);

      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'Zeta tr',
          status: 'needs_review');
      await insertRawVersion(
          id: 'v2',
          unitId: 'u2',
          projectLanguageId: 'pl-1',
          translatedText: null,
          status: 'needs_review');
      await insertRawVersion(
          id: 'v3',
          unitId: 'u3',
          projectLanguageId: 'pl-1',
          translatedText: 'Beta tr',
          status: 'needs_review');
      // Wrong status -> excluded.
      await insertRawUnit(id: 'u4', key: 'gamma');
      await insertRawVersion(
          id: 'v4',
          unitId: 'u4',
          projectLanguageId: 'pl-1',
          status: 'translated');
      // Wrong language -> excluded.
      await insertRawUnit(id: 'u5', key: 'delta', projectId: 'proj-1');
      await insertRawVersion(
          id: 'v5',
          unitId: 'u5',
          projectLanguageId: 'pl-OTHER',
          status: 'needs_review');

      final result = await repo.getNeedsReviewRows(projectLanguageId: 'pl-1');

      expect(result.isOk, isTrue);
      final rows = result.value;
      // Only u1 (zeta) and u2 (alpha); ordered by key -> alpha then zeta.
      expect(rows.map((r) => r.key).toList(), equals(['alpha', 'zeta']));

      final alpha = rows.firstWhere((r) => r.key == 'alpha');
      expect(alpha.unitId, equals('u2'));
      expect(alpha.versionId, equals('v2'));
      expect(alpha.sourceText, equals('Alpha source'));
      expect(alpha.translatedText, isNull,
          reason: 'null translation preserved as null');

      final zeta = rows.firstWhere((r) => r.key == 'zeta');
      expect(zeta.versionId, equals('v1'));
      expect(zeta.translatedText, equals('Zeta tr'));
    });

    test('returns empty list when no needs_review rows exist for the language',
        () async {
      await insertRawUnit(id: 'u1', key: 'k1');
      await insertRawVersion(
          id: 'v1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          status: 'translated');

      final result = await repo.getNeedsReviewRows(projectLanguageId: 'pl-1');

      expect(result.isOk, isTrue);
      expect(result.value, isEmpty);
    });
  });
}
