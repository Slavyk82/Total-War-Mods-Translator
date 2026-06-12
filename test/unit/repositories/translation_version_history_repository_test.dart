import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/domain/translation_version_history.dart';
import 'package:twmt/repositories/translation_version_history_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationVersionHistoryRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = TranslationVersionHistoryRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('TranslationVersionHistoryRepository', () {
    // Base timestamp kept small (in SECONDS, per schema convention) so
    // ordering-by-time assertions stay deterministic across rows.
    const baseTs = 1000;

    TranslationVersionHistory createEntry({
      String? id,
      String? versionId,
      String? translatedText,
      TranslationVersionStatus? status,
      String? changedBy,
      String? changeReason,
      int? createdAt,
    }) {
      return TranslationVersionHistory(
        id: id ?? 'history-id',
        versionId: versionId ?? 'version-1',
        translatedText: translatedText ?? 'translated text',
        status: status ?? TranslationVersionStatus.translated,
        changedBy: changedBy ?? 'user',
        changeReason: changeReason,
        createdAt: createdAt ?? baseTs,
      );
    }

    group('insert', () {
      test('should insert an entry successfully', () async {
        final entry = createEntry();

        final result = await repository.insert(entry);

        expect(result.isOk, isTrue);
        expect(result.value, equals(entry));

        final maps = await db.query(
          'translation_version_history',
          where: 'id = ?',
          whereArgs: [entry.id],
        );
        expect(maps.length, equals(1));
        expect(maps.first['version_id'], equals('version-1'));
        expect(maps.first['status'], equals('translated'));
        expect(maps.first['changed_by'], equals('user'));
        expect(maps.first['created_at'], equals(baseTs));
      });

      test('should persist needs_review status as serialized db value',
          () async {
        final entry = createEntry(
          id: 'h-needs',
          status: TranslationVersionStatus.needsReview,
        );

        final result = await repository.insert(entry);

        expect(result.isOk, isTrue);
        final maps = await db.query(
          'translation_version_history',
          where: 'id = ?',
          whereArgs: ['h-needs'],
        );
        expect(maps.first['status'], equals('needs_review'));
      });

      test('should fail when inserting duplicate id', () async {
        final entry = createEntry();
        await repository.insert(entry);

        final duplicate = createEntry(translatedText: 'other');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });
    });

    group('insertBatch', () {
      test('should insert multiple entries in one transaction', () async {
        final entries = [
          createEntry(id: 'b1', createdAt: baseTs),
          createEntry(id: 'b2', createdAt: baseTs + 1),
          createEntry(id: 'b3', createdAt: baseTs + 2),
        ];

        final result = await repository.insertBatch(entries);

        expect(result.isOk, isTrue);
        final countResult = await repository.count();
        expect(countResult.value, equals(3));
      });

      test('should return Ok for an empty list without writing rows', () async {
        final result = await repository.insertBatch([]);

        expect(result.isOk, isTrue);
        final countResult = await repository.count();
        expect(countResult.value, equals(0));
      });

      test('should roll back the whole batch on a duplicate id', () async {
        await repository.insert(createEntry(id: 'dup'));

        final result = await repository.insertBatch([
          createEntry(id: 'ok-new'),
          createEntry(id: 'dup'), // collides -> aborts transaction
        ]);

        expect(result.isErr, isTrue);
        // The good row must not have been committed (transaction rollback).
        final getOk = await repository.getById('ok-new');
        expect(getOk.isErr, isTrue);
        final countResult = await repository.count();
        expect(countResult.value, equals(1)); // only the pre-existing 'dup'
      });
    });

    group('getById', () {
      test('should return entry when found', () async {
        final entry = createEntry(id: 'g1');
        await repository.insert(entry);

        final result = await repository.getById('g1');

        expect(result.isOk, isTrue);
        expect(result.value.id, equals('g1'));
        expect(result.value.versionId, equals('version-1'));
        expect(result.value.status, equals(TranslationVersionStatus.translated));
      });

      test('should return error when not found', () async {
        final result = await repository.getById('missing');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no entries exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all entries ordered by created_at DESC', () async {
        await repository.insert(createEntry(id: 'old', createdAt: baseTs));
        await repository.insert(createEntry(id: 'new', createdAt: baseTs + 100));
        await repository.insert(createEntry(id: 'mid', createdAt: baseTs + 50));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('new'));
        expect(result.value[1].id, equals('mid'));
        expect(result.value[2].id, equals('old'));
      });
    });

    group('update', () {
      test('should update an existing entry', () async {
        final entry = createEntry(id: 'u1');
        await repository.insert(entry);

        final updated = entry.copyWith(
          translatedText: 'updated text',
          status: TranslationVersionStatus.needsReview,
        );
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.translatedText, equals('updated text'));

        final getResult = await repository.getById('u1');
        expect(getResult.value.translatedText, equals('updated text'));
        expect(
          getResult.value.status,
          equals(TranslationVersionStatus.needsReview),
        );
      });

      test('should return error when entry not found', () async {
        final entry = createEntry(id: 'nope');

        final result = await repository.update(entry);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete an existing entry', () async {
        final entry = createEntry(id: 'd1');
        await repository.insert(entry);

        final result = await repository.delete('d1');

        expect(result.isOk, isTrue);
        final getResult = await repository.getById('d1');
        expect(getResult.isErr, isTrue);
      });

      test('should return error when entry not found', () async {
        final result = await repository.delete('missing');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByVersion', () {
      test('should return only entries for the version, newest first',
          () async {
        await repository.insert(
            createEntry(id: 'v1a', versionId: 'ver-A', createdAt: baseTs));
        await repository.insert(
            createEntry(id: 'v1b', versionId: 'ver-A', createdAt: baseTs + 10));
        await repository.insert(
            createEntry(id: 'v2', versionId: 'ver-B', createdAt: baseTs));

        final result = await repository.getByVersion('ver-A');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('v1b')); // newest first
        expect(result.value[1].id, equals('v1a'));
      });

      test('should return empty list for unknown version', () async {
        final result = await repository.getByVersion('no-such-version');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getByVersionPaginated', () {
      test('should respect limit and offset, ordered DESC', () async {
        for (var i = 0; i < 5; i++) {
          await repository.insert(createEntry(
            id: 'p$i',
            versionId: 'ver-P',
            createdAt: baseTs + i,
          ));
        }

        final page = await repository.getByVersionPaginated(
          'ver-P',
          limit: 2,
          offset: 1,
        );

        expect(page.isOk, isTrue);
        expect(page.value.length, equals(2));
        // Full DESC order is p4,p3,p2,p1,p0; offset 1 -> p3,p2.
        expect(page.value[0].id, equals('p3'));
        expect(page.value[1].id, equals('p2'));
      });

      test('should return empty list when offset exceeds count', () async {
        await repository.insert(createEntry(id: 'single', versionId: 'ver-P'));

        final page = await repository.getByVersionPaginated(
          'ver-P',
          limit: 10,
          offset: 5,
        );

        expect(page.isOk, isTrue);
        expect(page.value, isEmpty);
      });
    });

    group('getByChangedBy', () {
      test('should return entries matching the changed_by attribution',
          () async {
        await repository.insert(
            createEntry(id: 'c1', changedBy: 'user', createdAt: baseTs));
        await repository.insert(createEntry(
            id: 'c2', changedBy: 'provider_anthropic', createdAt: baseTs + 1));
        await repository.insert(
            createEntry(id: 'c3', changedBy: 'user', createdAt: baseTs + 2));

        final result = await repository.getByChangedBy('user');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('c3')); // DESC
        expect(result.value[1].id, equals('c1'));
      });

      test('should return empty list when no entries match', () async {
        await repository.insert(createEntry(id: 'c1', changedBy: 'user'));

        final result = await repository.getByChangedBy('system');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('deleteOlderThan', () {
      test('should delete entries strictly before the timestamp', () async {
        await repository.insert(createEntry(id: 'old1', createdAt: baseTs));
        await repository.insert(createEntry(id: 'old2', createdAt: baseTs + 5));
        await repository.insert(createEntry(id: 'keep', createdAt: baseTs + 20));

        final result = await repository.deleteOlderThan(baseTs + 10);

        expect(result.isOk, isTrue);
        expect(result.value, equals(2)); // old1 + old2 removed

        final remaining = await repository.getAll();
        expect(remaining.value.length, equals(1));
        expect(remaining.value.first.id, equals('keep'));
      });

      test('should return 0 when nothing is older than the timestamp',
          () async {
        await repository.insert(createEntry(id: 'recent', createdAt: baseTs));

        final result = await repository.deleteOlderThan(baseTs);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0)); // boundary is exclusive (< timestamp)
      });
    });

    group('count', () {
      test('should return the total number of entries', () async {
        await repository.insert(createEntry(id: 'n1'));
        await repository.insert(createEntry(id: 'n2'));

        final result = await repository.count();

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('should return 0 when table is empty', () async {
        final result = await repository.count();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('countByVersion', () {
      test('should count only entries for the given version', () async {
        await repository.insert(createEntry(id: 'a1', versionId: 'ver-X'));
        await repository.insert(createEntry(id: 'a2', versionId: 'ver-X'));
        await repository.insert(createEntry(id: 'b1', versionId: 'ver-Y'));

        final result = await repository.countByVersion('ver-X');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('should return 0 for an unknown version', () async {
        await repository.insert(createEntry(id: 'a1', versionId: 'ver-X'));

        final result = await repository.countByVersion('ver-unknown');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('getStatistics', () {
      test('should group counts by changed_by', () async {
        await repository.insert(createEntry(id: 's1', changedBy: 'user'));
        await repository.insert(createEntry(id: 's2', changedBy: 'user'));
        await repository
            .insert(createEntry(id: 's3', changedBy: 'provider_anthropic'));

        final result = await repository.getStatistics();

        expect(result.isOk, isTrue);
        expect(result.value['user'], equals(2));
        expect(result.value['provider_anthropic'], equals(1));
        expect(result.value.length, equals(2));
      });

      test('should return empty map when table is empty', () async {
        final result = await repository.getStatistics();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getMostRecent', () {
      test('should return the newest entry for the version', () async {
        await repository.insert(
            createEntry(id: 'r1', versionId: 'ver-R', createdAt: baseTs));
        await repository.insert(
            createEntry(id: 'r2', versionId: 'ver-R', createdAt: baseTs + 50));

        final result = await repository.getMostRecent('ver-R');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals('r2'));
      });

      test('should return null when no entry exists for the version',
          () async {
        final result = await repository.getMostRecent('ver-empty');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('getTimeRange', () {
      test('should return earliest and latest timestamps', () async {
        await repository.insert(createEntry(id: 't1', createdAt: baseTs));
        await repository.insert(createEntry(id: 't2', createdAt: baseTs + 999));
        await repository.insert(createEntry(id: 't3', createdAt: baseTs + 500));

        final result = await repository.getTimeRange();

        expect(result.isOk, isTrue);
        expect(result.value['oldest'], equals(baseTs));
        expect(result.value['newest'], equals(baseTs + 999));
      });

      test('should return null bounds when table is empty', () async {
        final result = await repository.getTimeRange();

        expect(result.isOk, isTrue);
        expect(result.value['oldest'], isNull);
        expect(result.value['newest'], isNull);
      });
    });

    group('countReverts', () {
      test('should count entries whose change_reason mentions revert',
          () async {
        // Matches: LIKE '%Reverted%' or LIKE '%revert%'
        await repository.insert(createEntry(
            id: 'rv1', changeReason: 'Reverted to previous version'));
        await repository.insert(
            createEntry(id: 'rv2', changeReason: 'manual revert by user'));
        // Non-revert reasons / null reason must not be counted.
        await repository
            .insert(createEntry(id: 'rv3', changeReason: 'manual_edit'));
        await repository.insert(createEntry(id: 'rv4', changeReason: null));

        final result = await repository.countReverts();

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('should return 0 when no revert reasons are present', () async {
        await repository
            .insert(createEntry(id: 'nr1', changeReason: 'quality_improvement'));
        await repository.insert(createEntry(id: 'nr2', changeReason: null));

        final result = await repository.countReverts();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });
  });
}
