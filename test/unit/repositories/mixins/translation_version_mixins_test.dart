import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';

import '../../../helpers/test_database.dart';

/// Tests for the statistics and batch mixins applied to
/// [TranslationVersionRepository].
///
/// Mixin methods are exercised through the host class (the only way they can
/// be instantiated): `final repository = TranslationVersionRepository();`.
///
/// Schema notes that drive the seed data below:
/// - `translation_versions.status` CHECK allows
///   ('pending','translating','translated','reviewed','approved','needs_review').
///   There is NO 'error' status, so `countErrorByProject` (filters
///   status = 'error') can never count a real row — it is asserted to be 0.
/// - `excludeSkipUnitsCondition` filters on `tu.source_text`: '[HIDDEN]…'
///   prefixes, fully single-bracketed placeholders like '[hidden]', and the
///   uninitialized-filter defaults 'placeholder'/'dummy' (case-insensitive).
///   Counted units therefore use a plain source text ('src').
/// - `*_at` columns are Unix SECONDS; CHECK enforces created_at <= updated_at.
void main() {
  late Database db;
  late TranslationVersionRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = TranslationVersionRepository();
  });

  tearDown(() => TestDatabase.close(db));

  // ---- Raw seed helpers (bypass the model so we can write statuses the Dart
  // enum doesn't expose, e.g. 'approved'/'reviewed'/'translating'). ----

  Future<void> insertUnit(
    String id, {
    String projectId = 'proj-1',
    String? sourceText,
    int isObsolete = 0,
  }) async {
    await db.insert('translation_units', {
      'id': id,
      'project_id': projectId,
      'key': 'key-$id',
      'source_text': sourceText ?? 'src',
      'is_obsolete': isObsolete,
      'created_at': 1000,
      'updated_at': 1000,
    });
  }

  Future<void> insertVersion({
    required String id,
    required String unitId,
    required String projectLanguageId,
    String? translatedText,
    String status = 'pending',
    String translationSource = 'unknown',
  }) async {
    await db.insert('translation_versions', {
      'id': id,
      'unit_id': unitId,
      'project_language_id': projectLanguageId,
      'translated_text': translatedText,
      'status': status,
      'translation_source': translationSource,
      'created_at': 1000,
      'updated_at': 1000,
    });
  }

  // ===========================================================================
  // STATISTICS MIXIN
  // ===========================================================================
  group('TranslationVersionStatisticsMixin', () {
    group('countByProjectLanguage', () {
      test('counts all rows for the project language', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertVersion(id: 'v1', unitId: 'u1', projectLanguageId: 'pl-1');
        await insertVersion(id: 'v2', unitId: 'u2', projectLanguageId: 'pl-1');
        // Different project language → excluded.
        await insertVersion(id: 'v3', unitId: 'u3', projectLanguageId: 'pl-2');

        final result = await repository.countByProjectLanguage('pl-1');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('returns 0 when no rows match', () async {
        final result = await repository.countByProjectLanguage('pl-empty');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('countTranslatedByProjectLanguage', () {
      test('counts rows with non-empty translated_text', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            translatedText: 'hello');
        // Empty string → not counted.
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            translatedText: '');
        // NULL → not counted.
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            translatedText: null);

        final result =
            await repository.countTranslatedByProjectLanguage('pl-1');

        expect(result.isOk, isTrue);
        expect(result.value, equals(1));
      });

      test('returns 0 when nothing translated', () async {
        final result =
            await repository.countTranslatedByProjectLanguage('pl-empty');

        expect(result.value, equals(0));
      });
    });

    group('countValidatedByProjectLanguage', () {
      test('counts approved + reviewed rows', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            status: 'approved');
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            status: 'reviewed');
        // translated → not validated.
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            status: 'translated');

        final result =
            await repository.countValidatedByProjectLanguage('pl-1');

        expect(result.value, equals(2));
      });

      test('returns 0 when none validated', () async {
        final result =
            await repository.countValidatedByProjectLanguage('pl-empty');

        expect(result.value, equals(0));
      });
    });

    group('countNeedsReviewByProjectLanguage', () {
      test('counts needs_review rows', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            status: 'needs_review');
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            status: 'translated');

        final result =
            await repository.countNeedsReviewByProjectLanguage('pl-1');

        expect(result.value, equals(1));
      });

      test('returns 0 when none need review', () async {
        final result =
            await repository.countNeedsReviewByProjectLanguage('pl-empty');

        expect(result.value, equals(0));
      });
    });

    group('countTranslatedByProject', () {
      test('counts distinct non-obsolete units with translated text, '
          'excluding skip units', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3', isObsolete: 1); // obsolete → excluded
        await insertUnit('u4', sourceText: '[hidden]'); // bracketed → excluded
        await insertUnit('u5', sourceText: 'placeholder'); // default skip
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            translatedText: 'a');
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            translatedText: 'b');
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            translatedText: 'c');
        await insertVersion(
            id: 'v4',
            unitId: 'u4',
            projectLanguageId: 'pl-1',
            translatedText: 'd');
        await insertVersion(
            id: 'v5',
            unitId: 'u5',
            projectLanguageId: 'pl-1',
            translatedText: 'e');

        final result = await repository.countTranslatedByProject('proj-1');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('returns 0 for project with no data', () async {
        final result = await repository.countTranslatedByProject('proj-none');

        expect(result.value, equals(0));
      });
    });

    group('countPendingByProject', () {
      test('counts distinct non-obsolete pending units', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertVersion(
            id: 'v1', unitId: 'u1', projectLanguageId: 'pl-1', status: 'pending');
        await insertVersion(
            id: 'v2', unitId: 'u2', projectLanguageId: 'pl-1', status: 'pending');
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            status: 'translated');

        final result = await repository.countPendingByProject('proj-1');

        expect(result.value, equals(2));
      });

      test('returns 0 when nothing pending', () async {
        final result = await repository.countPendingByProject('proj-none');

        expect(result.value, equals(0));
      });
    });

    group('countValidatedByProject', () {
      test('counts distinct approved + reviewed units', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            status: 'approved');
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            status: 'reviewed');
        await insertVersion(
            id: 'v3', unitId: 'u3', projectLanguageId: 'pl-1', status: 'pending');

        final result = await repository.countValidatedByProject('proj-1');

        expect(result.value, equals(2));
      });

      test('returns 0 when none validated', () async {
        final result = await repository.countValidatedByProject('proj-none');

        expect(result.value, equals(0));
      });
    });

    group('countErrorByProject', () {
      test('always 0 because no row may have status = error '
          '(schema CHECK forbids it)', () async {
        await insertUnit('u1');
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            status: 'needs_review');

        final result = await repository.countErrorByProject('proj-1');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('returns 0 for project with no data', () async {
        final result = await repository.countErrorByProject('proj-none');

        expect(result.value, equals(0));
      });
    });

    group('countTmSourcedByProject', () {
      test('counts distinct units sourced from TM with translated text', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertUnit('u4');
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            translatedText: 'a',
            translationSource: 'tm_exact');
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            translatedText: 'b',
            translationSource: 'tm_fuzzy');
        // Manual source → excluded.
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            translatedText: 'c',
            translationSource: 'manual');
        // TM source but empty text → excluded.
        await insertVersion(
            id: 'v4',
            unitId: 'u4',
            projectLanguageId: 'pl-1',
            translatedText: '',
            translationSource: 'tm_exact');

        final result = await repository.countTmSourcedByProject('proj-1');

        expect(result.value, equals(2));
      });

      test('returns 0 when no TM-sourced translations', () async {
        final result = await repository.countTmSourcedByProject('proj-none');

        expect(result.value, equals(0));
      });
    });

    group('getProjectStatistics', () {
      test('aggregates best-status-per-unit counts', () async {
        // One unit per status bucket.
        await insertUnit('u-translated');
        await insertUnit('u-pending');
        await insertUnit('u-translating');
        await insertUnit('u-validated'); // approved
        await insertUnit('u-reviewed');
        await insertUnit('u-needsreview');
        await insertUnit('u-obsolete', isObsolete: 1);
        await insertUnit('u-skip', sourceText: '[hidden]');

        await insertVersion(
            id: 'v1',
            unitId: 'u-translated',
            projectLanguageId: 'pl-1',
            status: 'translated');
        await insertVersion(
            id: 'v2',
            unitId: 'u-pending',
            projectLanguageId: 'pl-1',
            status: 'pending');
        await insertVersion(
            id: 'v3',
            unitId: 'u-translating',
            projectLanguageId: 'pl-1',
            status: 'translating');
        await insertVersion(
            id: 'v4',
            unitId: 'u-validated',
            projectLanguageId: 'pl-1',
            status: 'approved');
        await insertVersion(
            id: 'v5',
            unitId: 'u-reviewed',
            projectLanguageId: 'pl-1',
            status: 'reviewed');
        await insertVersion(
            id: 'v6',
            unitId: 'u-needsreview',
            projectLanguageId: 'pl-1',
            status: 'needs_review');
        await insertVersion(
            id: 'v7',
            unitId: 'u-obsolete',
            projectLanguageId: 'pl-1',
            status: 'translated');
        await insertVersion(
            id: 'v8',
            unitId: 'u-skip',
            projectLanguageId: 'pl-1',
            status: 'translated');

        final result = await repository.getProjectStatistics('proj-1');

        expect(result.isOk, isTrue);
        final stats = result.value;
        // status_priority = 4 → translated.
        expect(stats.translatedCount, equals(1));
        // status_priority <= 2 → pending + translating.
        expect(stats.pendingCount, equals(2));
        // status_priority >= 5 → approved + reviewed.
        expect(stats.validatedCount, equals(2));
        // status_priority = 3 → needs_review (the model's "errorCount").
        expect(stats.errorCount, equals(1));
        // getProjectStatistics does not populate totalCount.
        expect(stats.totalCount, equals(0));
      });

      test('collapses multiple versions of one unit to its best status', () async {
        await insertUnit('u1');
        // Two project languages for the same unit → two versions.
        await insertVersion(
            id: 'v-low',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            status: 'pending');
        await insertVersion(
            id: 'v-high',
            unitId: 'u1',
            projectLanguageId: 'pl-2',
            status: 'approved');

        final result = await repository.getProjectStatistics('proj-1');

        final stats = result.value;
        // Best status for the single unit is 'approved' → validated only.
        expect(stats.validatedCount, equals(1));
        expect(stats.pendingCount, equals(0));
        expect(stats.translatedCount, equals(0));
      });

      test('returns all-zero stats for project with no units', () async {
        final result = await repository.getProjectStatistics('proj-none');

        expect(result.isOk, isTrue);
        final stats = result.value;
        expect(stats.translatedCount, equals(0));
        expect(stats.pendingCount, equals(0));
        expect(stats.validatedCount, equals(0));
        expect(stats.errorCount, equals(0));
      });
    });

    group('getLanguageStatistics', () {
      test('aggregates per-status counts for a project language', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertUnit('u4');
        await insertUnit('u5');
        await insertUnit('u6', isObsolete: 1); // excluded
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            status: 'translated');
        await insertVersion(
            id: 'v2', unitId: 'u2', projectLanguageId: 'pl-1', status: 'pending');
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            status: 'translating');
        await insertVersion(
            id: 'v4',
            unitId: 'u4',
            projectLanguageId: 'pl-1',
            status: 'approved');
        await insertVersion(
            id: 'v5',
            unitId: 'u5',
            projectLanguageId: 'pl-1',
            status: 'needs_review');
        await insertVersion(
            id: 'v6',
            unitId: 'u6',
            projectLanguageId: 'pl-1',
            status: 'translated');

        final result = await repository.getLanguageStatistics('pl-1');

        expect(result.isOk, isTrue);
        final stats = result.value;
        // Total counts non-obsolete, non-skip rows for the language (5).
        expect(stats.totalCount, equals(5));
        expect(stats.translatedCount, equals(1));
        // pending + translating.
        expect(stats.pendingCount, equals(2));
        // approved + reviewed.
        expect(stats.validatedCount, equals(1));
        // needs_review (model "errorCount").
        expect(stats.errorCount, equals(1));
      });

      test('returns all-zero stats when language has no rows', () async {
        final result = await repository.getLanguageStatistics('pl-empty');

        expect(result.isOk, isTrue);
        final stats = result.value;
        expect(stats.totalCount, equals(0));
        expect(stats.translatedCount, equals(0));
        expect(stats.pendingCount, equals(0));
        expect(stats.validatedCount, equals(0));
        expect(stats.errorCount, equals(0));
      });
    });

    group('getGlobalStatistics', () {
      test('counts units, translated units, pending units and words', () async {
        await insertUnit('u1');
        await insertUnit('u2');
        await insertUnit('u3');
        await insertUnit('u4', isObsolete: 1); // excluded
        await insertUnit('u5', sourceText: 'dummy'); // default skip → excluded
        // u1: translated with two words.
        await insertVersion(
            id: 'v1',
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            translatedText: 'hello world');
        // u2: translated with one word.
        await insertVersion(
            id: 'v2',
            unitId: 'u2',
            projectLanguageId: 'pl-1',
            translatedText: 'bonjour');
        // u3: no translation → pending.
        await insertVersion(
            id: 'v3',
            unitId: 'u3',
            projectLanguageId: 'pl-1',
            translatedText: null);
        await insertVersion(
            id: 'v4',
            unitId: 'u4',
            projectLanguageId: 'pl-1',
            translatedText: 'obsolete');
        await insertVersion(
            id: 'v5',
            unitId: 'u5',
            projectLanguageId: 'pl-1',
            translatedText: 'skip');

        final result = await repository.getGlobalStatistics();

        expect(result.isOk, isTrue);
        final stats = result.value;
        // u1, u2, u3 are the non-obsolete, non-skip units.
        expect(stats.totalUnits, equals(3));
        expect(stats.translatedUnits, equals(2));
        expect(stats.pendingUnits, equals(1));
        // Word approximation = spaces + 1 summed: 'hello world' (2) + 'bonjour' (1).
        expect(stats.totalTranslatedWords, equals(3));
      });

      test('returns empty stats when there is no data', () async {
        final result = await repository.getGlobalStatistics();

        expect(result.isOk, isTrue);
        final stats = result.value;
        expect(stats.totalUnits, equals(0));
        expect(stats.translatedUnits, equals(0));
        expect(stats.pendingUnits, equals(0));
        expect(stats.totalTranslatedWords, equals(0));
      });
    });
  });

  // ===========================================================================
  // BATCH MIXIN
  // ===========================================================================
  group('TranslationVersionBatchMixin', () {
    TranslationVersion makeVersion({
      required String id,
      required String unitId,
      String projectLanguageId = 'pl-1',
      String? translatedText,
      TranslationVersionStatus status = TranslationVersionStatus.pending,
      TranslationSource source = TranslationSource.unknown,
      int createdAt = 1000,
      int updatedAt = 1000,
    }) {
      return TranslationVersion(
        id: id,
        unitId: unitId,
        projectLanguageId: projectLanguageId,
        translatedText: translatedText,
        status: status,
        translationSource: source,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
    }

    group('insertBatch', () {
      test('inserts all entities in one transaction', () async {
        final entities = [
          makeVersion(id: 'v1', unitId: 'u1', translatedText: 'a'),
          makeVersion(id: 'v2', unitId: 'u2', translatedText: 'b'),
          makeVersion(id: 'v3', unitId: 'u3', translatedText: 'c'),
        ];

        final result = await repository.insertBatch(entities);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));

        final rows = await db.query('translation_versions', orderBy: 'id ASC');
        expect(rows.length, equals(3));
        expect(rows[0]['id'], equals('v1'));
        expect(rows[0]['translated_text'], equals('a'));
        expect(rows[2]['id'], equals('v3'));
      });

      test('returns Ok with empty list and writes nothing for empty input',
          () async {
        final result = await repository.insertBatch([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);

        final rows = await db.query('translation_versions');
        expect(rows, isEmpty);
      });

      test('fails when an entity collides with an existing primary key',
          () async {
        await insertVersion(id: 'v1', unitId: 'u1', projectLanguageId: 'pl-1');

        final result = await repository.insertBatch([
          makeVersion(id: 'v1', unitId: 'u2'), // duplicate PK → abort
        ]);

        expect(result.isErr, isTrue);
      });
    });

    group('upsertBatch', () {
      test('inserts new rows when no matching (unit, language) exists',
          () async {
        final result = await repository.upsertBatch([
          makeVersion(id: 'v1', unitId: 'u1', translatedText: 'a'),
          makeVersion(id: 'v2', unitId: 'u2', translatedText: 'b'),
        ]);

        expect(result.isOk, isTrue);

        final rows = await db.query('translation_versions', orderBy: 'id ASC');
        expect(rows.length, equals(2));
        expect(rows[0]['id'], equals('v1'));
        expect(rows[1]['translated_text'], equals('b'));
      });

      test('updates existing row by (unit, language), preserving id and '
          'created_at', () async {
        await insertVersion(
          id: 'existing-1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'old',
          status: 'pending',
        );
        // Seeded created_at is 1000 (see insertVersion helper).

        final result = await repository.upsertBatch([
          makeVersion(
            id: 'ignored-id', // id ignored on UPDATE path
            unitId: 'u1',
            projectLanguageId: 'pl-1',
            translatedText: 'fresh',
            status: TranslationVersionStatus.translated,
            createdAt: 5000, // ignored: original created_at preserved
            updatedAt: 5000,
          ),
        ]);

        expect(result.isOk, isTrue);

        final rows = await db.query('translation_versions');
        expect(rows.length, equals(1));
        expect(rows.first['id'], equals('existing-1'));
        expect(rows.first['translated_text'], equals('fresh'));
        expect(rows.first['status'], equals('translated'));
        expect(rows.first['created_at'], equals(1000),
            reason: 'created_at must be preserved from the existing row');
      });

      test('handles a mix of insert and update in one call', () async {
        await insertVersion(
          id: 'pre-1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'old',
        );

        final result = await repository.upsertBatch([
          // Updates pre-1 (same unit+language).
          makeVersion(
              id: 'ignored',
              unitId: 'u1',
              projectLanguageId: 'pl-1',
              translatedText: 'updated'),
          // Inserts a brand new row.
          makeVersion(
              id: 'new-2',
              unitId: 'u2',
              projectLanguageId: 'pl-1',
              translatedText: 'brand new'),
        ]);

        expect(result.isOk, isTrue);

        final rows = await db.query('translation_versions', orderBy: 'id ASC');
        expect(rows.length, equals(2));
        // Existing row updated in place.
        final pre = rows.firstWhere((r) => r['id'] == 'pre-1');
        expect(pre['translated_text'], equals('updated'));
        // New row inserted with its own id.
        final fresh = rows.firstWhere((r) => r['id'] == 'new-2');
        expect(fresh['translated_text'], equals('brand new'));
      });

      test('returns Ok with empty list for empty input', () async {
        final result = await repository.upsertBatch([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);

        final rows = await db.query('translation_versions');
        expect(rows, isEmpty);
      });
    });

    group('importBatch', () {
      test('inserts rows when no existingVersionIds mapping is given', () async {
        final entities = [
          makeVersion(id: 'v1', unitId: 'u1', translatedText: 'a'),
          makeVersion(id: 'v2', unitId: 'u2', translatedText: 'b'),
        ];

        final result = await repository.importBatch(
          entities: entities,
          existingVersionIds: const {},
        );

        expect(result.isOk, isTrue);
        final counts = result.value;
        expect(counts.inserted, equals(2));
        expect(counts.updated, equals(0));
        expect(counts.skipped, equals(0));

        final rows = await db.query('translation_versions');
        expect(rows.length, equals(2));
      });

      test('updates rows referenced by existingVersionIds', () async {
        await insertVersion(
          id: 'existing-1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'old',
          status: 'pending',
        );

        final result = await repository.importBatch(
          entities: [
            makeVersion(
              id: 'ignored', // id removed on the UPDATE path
              unitId: 'u1',
              projectLanguageId: 'pl-1',
              translatedText: 'imported',
              status: TranslationVersionStatus.translated,
            ),
          ],
          existingVersionIds: const {'u1': 'existing-1'},
        );

        expect(result.isOk, isTrue);
        final counts = result.value;
        expect(counts.inserted, equals(0));
        expect(counts.updated, equals(1));

        final rows = await db.query('translation_versions');
        expect(rows.length, equals(1));
        expect(rows.first['id'], equals('existing-1'));
        expect(rows.first['translated_text'], equals('imported'));
        expect(rows.first['status'], equals('translated'));
      });

      test('mixes inserts and updates with correct counts', () async {
        await insertVersion(
          id: 'existing-1',
          unitId: 'u1',
          projectLanguageId: 'pl-1',
          translatedText: 'old',
        );

        final result = await repository.importBatch(
          entities: [
            makeVersion(
                id: 'ignored',
                unitId: 'u1',
                projectLanguageId: 'pl-1',
                translatedText: 'updated'),
            makeVersion(
                id: 'new-2',
                unitId: 'u2',
                projectLanguageId: 'pl-1',
                translatedText: 'new'),
          ],
          existingVersionIds: const {'u1': 'existing-1'},
        );

        expect(result.isOk, isTrue);
        final counts = result.value;
        expect(counts.inserted, equals(1));
        expect(counts.updated, equals(1));

        final rows = await db.query('translation_versions', orderBy: 'id ASC');
        expect(rows.length, equals(2));
      });

      test('returns zero counts for empty input', () async {
        final result = await repository.importBatch(
          entities: const [],
          existingVersionIds: const {},
        );

        expect(result.isOk, isTrue);
        final counts = result.value;
        expect(counts.inserted, equals(0));
        expect(counts.updated, equals(0));
        expect(counts.skipped, equals(0));
      });

      test('rolls back and reports everything skipped when cancelled', () async {
        final result = await repository.importBatch(
          entities: [
            makeVersion(id: 'v1', unitId: 'u1', translatedText: 'a'),
            makeVersion(id: 'v2', unitId: 'u2', translatedText: 'b'),
          ],
          existingVersionIds: const {},
          isCancelled: () => true,
        );

        expect(result.isOk, isTrue);
        final counts = result.value;
        expect(counts.inserted, equals(0));
        expect(counts.updated, equals(0));
        expect(counts.skipped, equals(2));

        // Transaction rolled back → nothing persisted.
        final rows = await db.query('translation_versions');
        expect(rows, isEmpty);
      });
    });
  });
}
