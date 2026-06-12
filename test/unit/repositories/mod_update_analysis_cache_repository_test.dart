import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ModUpdateAnalysisCacheRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = ModUpdateAnalysisCacheRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ModUpdateAnalysisCacheRepository', () {
    ModUpdateAnalysisCache createCache({
      String? id,
      String? projectId,
      String? packFilePath,
      int? fileLastModified,
      int? newUnitsCount,
      int? removedUnitsCount,
      int? modifiedUnitsCount,
      int? totalPackUnits,
      int? totalProjectUnits,
      int? analyzedAt,
    }) {
      return ModUpdateAnalysisCache(
        id: id ?? 'cache-id',
        projectId: projectId ?? 'project-1',
        packFilePath: packFilePath ?? '/path/to/pack.pack',
        fileLastModified: fileLastModified ?? 1000,
        newUnitsCount: newUnitsCount ?? 0,
        removedUnitsCount: removedUnitsCount ?? 0,
        modifiedUnitsCount: modifiedUnitsCount ?? 0,
        totalPackUnits: totalPackUnits ?? 0,
        totalProjectUnits: totalProjectUnits ?? 0,
        analyzedAt: analyzedAt ?? 1000,
      );
    }

    group('insert', () {
      test('should insert a cache entry successfully', () async {
        final cache = createCache();

        final result = await repository.insert(cache);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals('cache-id'));

        final maps =
            await db.query('mod_update_analysis_cache', where: 'id = ?', whereArgs: ['cache-id']);
        expect(maps.length, equals(1));
        expect(maps.first['project_id'], equals('project-1'));
        expect(maps.first['pack_file_path'], equals('/path/to/pack.pack'));
      });

      test('should fail when inserting duplicate ID', () async {
        final cache = createCache();
        await repository.insert(cache);

        final duplicate = createCache(packFilePath: '/different/path.pack');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when violating UNIQUE(project_id, pack_file_path)', () async {
        await repository.insert(createCache(id: 'c1'));

        final result = await repository.insert(createCache(id: 'c2'));

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return cache entry when found', () async {
        final cache = createCache(newUnitsCount: 5, modifiedUnitsCount: 3);
        await repository.insert(cache);

        final result = await repository.getById('cache-id');

        expect(result.isOk, isTrue);
        expect(result.value.id, equals('cache-id'));
        expect(result.value.newUnitsCount, equals(5));
        expect(result.value.modifiedUnitsCount, equals(3));
      });

      test('should return error when not found', () async {
        final result = await repository.getById('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByProjectAndPath', () {
      test('should return cache entry when project + path match', () async {
        await repository.insert(createCache(
          projectId: 'proj-A',
          packFilePath: '/mods/a.pack',
        ));

        final result = await repository.getByProjectAndPath('proj-A', '/mods/a.pack');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.projectId, equals('proj-A'));
        expect(result.value!.packFilePath, equals('/mods/a.pack'));
      });

      test('should return null when no match', () async {
        await repository.insert(createCache(
          projectId: 'proj-A',
          packFilePath: '/mods/a.pack',
        ));

        final result = await repository.getByProjectAndPath('proj-A', '/other/path.pack');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('getByProjectId', () {
      test('should return all entries for a project', () async {
        await repository.insert(createCache(
          id: 'c1',
          projectId: 'proj-X',
          packFilePath: '/p1.pack',
        ));
        await repository.insert(createCache(
          id: 'c2',
          projectId: 'proj-X',
          packFilePath: '/p2.pack',
        ));
        await repository.insert(createCache(
          id: 'c3',
          projectId: 'proj-Y',
          packFilePath: '/p3.pack',
        ));

        final result = await repository.getByProjectId('proj-X');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((c) => c.projectId == 'proj-X'), isTrue);
      });

      test('should return empty list when project has no entries', () async {
        final result = await repository.getByProjectId('missing-project');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getByProjectIds', () {
      test('should return a map keyed by project id for matching entries', () async {
        await repository.insert(createCache(
          id: 'c1',
          projectId: 'proj-A',
          packFilePath: '/a.pack',
        ));
        await repository.insert(createCache(
          id: 'c2',
          projectId: 'proj-B',
          packFilePath: '/b.pack',
        ));
        await repository.insert(createCache(
          id: 'c3',
          projectId: 'proj-C',
          packFilePath: '/c.pack',
        ));

        final result = await repository.getByProjectIds(['proj-A', 'proj-C']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.containsKey('proj-A'), isTrue);
        expect(result.value.containsKey('proj-C'), isTrue);
        expect(result.value.containsKey('proj-B'), isFalse);
        expect(result.value['proj-A']!.id, equals('c1'));
      });

      test('should return empty map when project id list is empty', () async {
        await repository.insert(createCache());

        final result = await repository.getByProjectIds([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getAll', () {
      test('should return empty list when no entries exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all entries ordered by analyzed_at DESC', () async {
        await repository.insert(createCache(
          id: 'c1',
          packFilePath: '/p1.pack',
          analyzedAt: 1000,
        ));
        await repository.insert(createCache(
          id: 'c2',
          packFilePath: '/p2.pack',
          analyzedAt: 3000,
        ));
        await repository.insert(createCache(
          id: 'c3',
          packFilePath: '/p3.pack',
          analyzedAt: 2000,
        ));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].analyzedAt, equals(3000));
        expect(result.value[1].analyzedAt, equals(2000));
        expect(result.value[2].analyzedAt, equals(1000));
      });
    });

    group('upsert', () {
      test('should insert when entry does not exist', () async {
        final cache = createCache(newUnitsCount: 2);

        final result = await repository.upsert(cache);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('cache-id');
        expect(getResult.isOk, isTrue);
        expect(getResult.value.newUnitsCount, equals(2));
      });

      test('should replace existing entry with same id', () async {
        await repository.insert(createCache(newUnitsCount: 1));

        final updated = createCache(newUnitsCount: 99, modifiedUnitsCount: 7);
        final result = await repository.upsert(updated);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('cache-id');
        expect(getResult.value.newUnitsCount, equals(99));
        expect(getResult.value.modifiedUnitsCount, equals(7));

        // Still only one row.
        final maps = await db.query('mod_update_analysis_cache');
        expect(maps.length, equals(1));
      });
    });

    group('upsertBatch', () {
      test('should insert multiple entries', () async {
        final entities = [
          createCache(id: 'c1', packFilePath: '/p1.pack'),
          createCache(id: 'c2', packFilePath: '/p2.pack'),
          createCache(id: 'c3', packFilePath: '/p3.pack'),
        ];

        final result = await repository.upsertBatch(entities);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));

        final maps = await db.query('mod_update_analysis_cache');
        expect(maps.length, equals(3));
      });

      test('should handle empty list', () async {
        final result = await repository.upsertBatch([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);

        final maps = await db.query('mod_update_analysis_cache');
        expect(maps, isEmpty);
      });

      test('should replace existing entries on conflicting id', () async {
        await repository.insert(createCache(id: 'c1', newUnitsCount: 1));

        final result = await repository.upsertBatch([
          createCache(id: 'c1', newUnitsCount: 50),
        ]);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('c1');
        expect(getResult.value.newUnitsCount, equals(50));
      });
    });

    group('update', () {
      test('should update an existing entry', () async {
        await repository.insert(createCache(newUnitsCount: 1));

        final updated = createCache(newUnitsCount: 42, totalPackUnits: 100);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('cache-id');
        expect(getResult.value.newUnitsCount, equals(42));
        expect(getResult.value.totalPackUnits, equals(100));
      });

      test('should return error when entry not found', () async {
        final result = await repository.update(createCache(id: 'missing'));

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete an existing entry', () async {
        await repository.insert(createCache());

        final result = await repository.delete('cache-id');

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('cache-id');
        expect(getResult.isErr, isTrue);
      });

      test('should return error when entry not found', () async {
        final result = await repository.delete('missing');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('deleteByProjectId', () {
      test('should delete all entries for a project', () async {
        await repository.insert(createCache(
          id: 'c1',
          projectId: 'proj-X',
          packFilePath: '/p1.pack',
        ));
        await repository.insert(createCache(
          id: 'c2',
          projectId: 'proj-X',
          packFilePath: '/p2.pack',
        ));
        await repository.insert(createCache(
          id: 'c3',
          projectId: 'proj-Y',
          packFilePath: '/p3.pack',
        ));

        final result = await repository.deleteByProjectId('proj-X');

        expect(result.isOk, isTrue);

        final remaining = await repository.getByProjectId('proj-X');
        expect(remaining.value, isEmpty);
        final other = await repository.getByProjectId('proj-Y');
        expect(other.value.length, equals(1));
      });

      test('should succeed (no-op) when project has no entries', () async {
        final result = await repository.deleteByProjectId('no-such-project');

        expect(result.isOk, isTrue);
      });
    });

    group('deleteOlderThan', () {
      test('should delete only entries older than the threshold', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        // Old entry: analyzed well in the past.
        await repository.insert(createCache(
          id: 'old',
          packFilePath: '/old.pack',
          analyzedAt: now - 10000,
        ));
        // Fresh entry: analyzed recently.
        await repository.insert(createCache(
          id: 'fresh',
          packFilePath: '/fresh.pack',
          analyzedAt: now,
        ));

        // Threshold of 5000 seconds => cutoff = now - 5000.
        final result = await repository.deleteOlderThan(5000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(1));

        expect((await repository.getById('old')).isErr, isTrue);
        expect((await repository.getById('fresh')).isOk, isTrue);
      });

      test('should return 0 when nothing is older than the threshold', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await repository.insert(createCache(analyzedAt: now));

        final result = await repository.deleteOlderThan(5000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('deleteAllWithChanges', () {
      test('should delete entries that have any changes', () async {
        await repository.insert(createCache(
          id: 'new',
          packFilePath: '/new.pack',
          newUnitsCount: 1,
        ));
        await repository.insert(createCache(
          id: 'removed',
          packFilePath: '/removed.pack',
          removedUnitsCount: 2,
        ));
        await repository.insert(createCache(
          id: 'modified',
          packFilePath: '/modified.pack',
          modifiedUnitsCount: 3,
        ));
        await repository.insert(createCache(
          id: 'clean',
          packFilePath: '/clean.pack',
        ));

        final result = await repository.deleteAllWithChanges();

        expect(result.isOk, isTrue);
        expect(result.value, equals(3));

        final remaining = await repository.getAll();
        expect(remaining.value.length, equals(1));
        expect(remaining.value.first.id, equals('clean'));
      });

      test('should return 0 when no entry has changes', () async {
        await repository.insert(createCache());

        final result = await repository.deleteAllWithChanges();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('clearChangesForProject', () {
      test('should zero out all change counts for the matching entry', () async {
        await repository.insert(createCache(
          projectId: 'proj-A',
          packFilePath: '/a.pack',
          newUnitsCount: 5,
          removedUnitsCount: 4,
          modifiedUnitsCount: 3,
          totalPackUnits: 100,
        ));

        final result = await repository.clearChangesForProject('proj-A', '/a.pack');

        expect(result.isOk, isTrue);

        final getResult = await repository.getByProjectAndPath('proj-A', '/a.pack');
        expect(getResult.value, isNotNull);
        expect(getResult.value!.newUnitsCount, equals(0));
        expect(getResult.value!.removedUnitsCount, equals(0));
        expect(getResult.value!.modifiedUnitsCount, equals(0));
        // Non-change columns are untouched.
        expect(getResult.value!.totalPackUnits, equals(100));
      });

      test('should be a no-op when no entry matches', () async {
        await repository.insert(createCache(
          projectId: 'proj-A',
          packFilePath: '/a.pack',
          newUnitsCount: 5,
        ));

        final result = await repository.clearChangesForProject('proj-A', '/other.pack');

        expect(result.isOk, isTrue);

        // The non-matching entry is untouched.
        final getResult = await repository.getByProjectAndPath('proj-A', '/a.pack');
        expect(getResult.value!.newUnitsCount, equals(5));
      });
    });
  });
}
