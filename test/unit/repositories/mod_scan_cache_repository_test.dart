import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/repositories/mod_scan_cache_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ModScanCacheRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = ModScanCacheRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ModScanCacheRepository', () {
    ModScanCache createTestCache({
      String? id,
      String? packFilePath,
      int? fileLastModified,
      bool? hasLocFiles,
      int? scannedAt,
    }) {
      return ModScanCache(
        id: id ?? 'cache-id',
        packFilePath: packFilePath ?? 'C:/mods/example.pack',
        fileLastModified: fileLastModified ?? 1000,
        hasLocFiles: hasLocFiles ?? true,
        scannedAt: scannedAt ?? 2000,
      );
    }

    group('insert', () {
      test('should insert a cache entry successfully', () async {
        final cache = createTestCache();

        final result = await repository.insert(cache);

        expect(result.isOk, isTrue);
        expect(result.value, equals(cache));

        // Verify it's in the database.
        final maps = await db.query('mod_scan_cache',
            where: 'id = ?', whereArgs: [cache.id]);
        expect(maps.length, equals(1));
        expect(maps.first['pack_file_path'], equals('C:/mods/example.pack'));
        expect(maps.first['has_loc_files'], equals(1));
      });

      test('should store has_loc_files false as 0', () async {
        final cache = createTestCache(hasLocFiles: false);

        final result = await repository.insert(cache);

        expect(result.isOk, isTrue);
        final maps = await db.query('mod_scan_cache',
            where: 'id = ?', whereArgs: [cache.id]);
        expect(maps.first['has_loc_files'], equals(0));
      });

      test('should fail when inserting duplicate ID', () async {
        final cache = createTestCache();
        await repository.insert(cache);

        final duplicate =
            createTestCache(packFilePath: 'C:/mods/other.pack');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate pack_file_path', () async {
        final cache1 =
            createTestCache(id: 'c1', packFilePath: 'C:/mods/same.pack');
        await repository.insert(cache1);

        final cache2 =
            createTestCache(id: 'c2', packFilePath: 'C:/mods/same.pack');
        final result = await repository.insert(cache2);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return cache entry when found', () async {
        final cache = createTestCache();
        await repository.insert(cache);

        final result = await repository.getById(cache.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(cache.id));
        expect(result.value.packFilePath, equals(cache.packFilePath));
        expect(result.value.hasLocFiles, isTrue);
        expect(result.value.fileLastModified, equals(1000));
        expect(result.value.scannedAt, equals(2000));
      });

      test('should return error when not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByPackFilePath', () {
      test('should return cache entry when path found', () async {
        final cache = createTestCache(packFilePath: 'C:/mods/found.pack');
        await repository.insert(cache);

        final result =
            await repository.getByPackFilePath('C:/mods/found.pack');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.packFilePath, equals('C:/mods/found.pack'));
      });

      test('should return null when path not found', () async {
        final result =
            await repository.getByPackFilePath('C:/mods/missing.pack');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('getByPackFilePaths', () {
      test('should return map of found entries keyed by path', () async {
        final cache1 =
            createTestCache(id: 'c1', packFilePath: 'C:/mods/a.pack');
        final cache2 =
            createTestCache(id: 'c2', packFilePath: 'C:/mods/b.pack');
        await repository.insert(cache1);
        await repository.insert(cache2);

        final result = await repository.getByPackFilePaths(
            ['C:/mods/a.pack', 'C:/mods/b.pack', 'C:/mods/missing.pack']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value['C:/mods/a.pack']!.id, equals('c1'));
        expect(result.value['C:/mods/b.pack']!.id, equals('c2'));
        expect(result.value.containsKey('C:/mods/missing.pack'), isFalse);
      });

      test('should return empty map when given empty list', () async {
        final result = await repository.getByPackFilePaths([]);

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

      test('should return all entries ordered by scanned_at DESC', () async {
        final cache1 = createTestCache(
            id: 'c1', packFilePath: 'C:/mods/old.pack', scannedAt: 1000);
        final cache2 = createTestCache(
            id: 'c2', packFilePath: 'C:/mods/new.pack', scannedAt: 3000);
        final cache3 = createTestCache(
            id: 'c3', packFilePath: 'C:/mods/mid.pack', scannedAt: 2000);
        await repository.insert(cache1);
        await repository.insert(cache2);
        await repository.insert(cache3);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('c2')); // scannedAt 3000
        expect(result.value[1].id, equals('c3')); // scannedAt 2000
        expect(result.value[2].id, equals('c1')); // scannedAt 1000
      });
    });

    group('upsert', () {
      test('should insert when entry does not exist', () async {
        final cache = createTestCache();

        final result = await repository.upsert(cache);

        expect(result.isOk, isTrue);
        final getResult = await repository.getById(cache.id);
        expect(getResult.isOk, isTrue);
      });

      test('should replace existing entry with same pack_file_path',
          () async {
        final cache = createTestCache(
            id: 'c1',
            packFilePath: 'C:/mods/up.pack',
            fileLastModified: 1000);
        await repository.insert(cache);

        final updated = createTestCache(
            id: 'c1',
            packFilePath: 'C:/mods/up.pack',
            fileLastModified: 5000,
            hasLocFiles: false);
        final result = await repository.upsert(updated);

        expect(result.isOk, isTrue);
        final getResult = await repository.getById('c1');
        expect(getResult.value.fileLastModified, equals(5000));
        expect(getResult.value.hasLocFiles, isFalse);

        // Still exactly one row.
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(1));
      });
    });

    group('upsertBatch', () {
      test('should insert multiple entries', () async {
        final caches = [
          createTestCache(id: 'c1', packFilePath: 'C:/mods/1.pack'),
          createTestCache(id: 'c2', packFilePath: 'C:/mods/2.pack'),
          createTestCache(id: 'c3', packFilePath: 'C:/mods/3.pack'),
        ];

        final result = await repository.upsertBatch(caches);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(3));
      });

      test('should replace existing entries in batch', () async {
        await repository.insert(createTestCache(
            id: 'c1',
            packFilePath: 'C:/mods/1.pack',
            fileLastModified: 1000));

        final result = await repository.upsertBatch([
          createTestCache(
              id: 'c1',
              packFilePath: 'C:/mods/1.pack',
              fileLastModified: 9000),
          createTestCache(id: 'c2', packFilePath: 'C:/mods/2.pack'),
        ]);

        expect(result.isOk, isTrue);
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(2));
        final getResult = await repository.getById('c1');
        expect(getResult.value.fileLastModified, equals(9000));
      });

      test('should handle empty batch', () async {
        final result = await repository.upsertBatch([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(0));
      });
    });

    group('update', () {
      test('should update existing entry', () async {
        final cache = createTestCache();
        await repository.insert(cache);

        final updated = cache.copyWith(fileLastModified: 7777);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        final getResult = await repository.getById(cache.id);
        expect(getResult.value.fileLastModified, equals(7777));
      });

      test('should return error when entry not found', () async {
        final cache = createTestCache(id: 'non-existent');

        final result = await repository.update(cache);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete existing entry', () async {
        final cache = createTestCache();
        await repository.insert(cache);

        final result = await repository.delete(cache.id);

        expect(result.isOk, isTrue);
        final getResult = await repository.getById(cache.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when entry not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('deleteByPackFilePath', () {
      test('should delete entry by path', () async {
        final cache = createTestCache(packFilePath: 'C:/mods/del.pack');
        await repository.insert(cache);

        final result =
            await repository.deleteByPackFilePath('C:/mods/del.pack');

        expect(result.isOk, isTrue);
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(0));
      });

      test('should succeed when path does not exist (no-op)', () async {
        final cache = createTestCache(packFilePath: 'C:/mods/keep.pack');
        await repository.insert(cache);

        final result =
            await repository.deleteByPackFilePath('C:/mods/missing.pack');

        expect(result.isOk, isTrue);
        // Existing entry untouched.
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(1));
      });
    });

    group('deleteOlderThan', () {
      test('should delete entries older than threshold and return count',
          () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        // 'old' was scanned 10000s ago, 'fresh' was scanned just now.
        final oldCache = createTestCache(
            id: 'old',
            packFilePath: 'C:/mods/old.pack',
            scannedAt: now - 10000);
        final freshCache = createTestCache(
            id: 'fresh',
            packFilePath: 'C:/mods/fresh.pack',
            scannedAt: now);
        await repository.insert(oldCache);
        await repository.insert(freshCache);

        // Threshold of 5000s: anything scanned before now-5000 is deleted.
        final result = await repository.deleteOlderThan(5000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(1));
        final getOld = await repository.getById('old');
        expect(getOld.isErr, isTrue);
        final getFresh = await repository.getById('fresh');
        expect(getFresh.isOk, isTrue);
      });

      test('should return 0 when nothing is older than threshold', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        await repository.insert(createTestCache(
            id: 'fresh',
            packFilePath: 'C:/mods/fresh.pack',
            scannedAt: now));

        final result = await repository.deleteOlderThan(5000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('deleteOrphaned', () {
      test('should delete entries not in the provided path list', () async {
        await repository.insert(
            createTestCache(id: 'keep', packFilePath: 'C:/mods/keep.pack'));
        await repository.insert(createTestCache(
            id: 'orphan1', packFilePath: 'C:/mods/gone1.pack'));
        await repository.insert(createTestCache(
            id: 'orphan2', packFilePath: 'C:/mods/gone2.pack'));

        final result =
            await repository.deleteOrphaned(['C:/mods/keep.pack']);

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(1));
        expect(maps.first['id'], equals('keep'));
      });

      test('should delete all entries when given empty list', () async {
        await repository.insert(
            createTestCache(id: 'c1', packFilePath: 'C:/mods/1.pack'));
        await repository.insert(
            createTestCache(id: 'c2', packFilePath: 'C:/mods/2.pack'));

        final result = await repository.deleteOrphaned([]);

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(0));
      });

      test('should keep all entries when all paths still exist', () async {
        await repository.insert(
            createTestCache(id: 'c1', packFilePath: 'C:/mods/1.pack'));
        await repository.insert(
            createTestCache(id: 'c2', packFilePath: 'C:/mods/2.pack'));

        final result = await repository
            .deleteOrphaned(['C:/mods/1.pack', 'C:/mods/2.pack']);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
        final maps = await db.query('mod_scan_cache');
        expect(maps.length, equals(2));
      });
    });
  });
}
