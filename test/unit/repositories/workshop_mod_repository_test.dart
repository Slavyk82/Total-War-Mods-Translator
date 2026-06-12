import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/workshop_mod_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late WorkshopModRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = WorkshopModRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('WorkshopModRepository', () {
    final int nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    WorkshopMod createTestMod({
      String? id,
      String? workshopId,
      String? title,
      int? appId,
      String? workshopUrl,
      int? fileSize,
      int? timeCreated,
      int? timeUpdated,
      int? subscriptions,
      List<String>? tags,
      int? createdAt,
      int? updatedAt,
      int? lastCheckedAt,
      bool isHidden = false,
    }) {
      return WorkshopMod(
        id: id ?? 'mod-id',
        workshopId: workshopId ?? '123456789',
        title: title ?? 'Test Mod',
        appId: appId ?? 594570,
        workshopUrl: workshopUrl ??
            'https://steamcommunity.com/sharedfiles/filedetails/?id=123456789',
        fileSize: fileSize,
        timeCreated: timeCreated,
        timeUpdated: timeUpdated,
        subscriptions: subscriptions,
        tags: tags,
        createdAt: createdAt ?? nowSeconds,
        updatedAt: updatedAt ?? nowSeconds,
        lastCheckedAt: lastCheckedAt,
        isHidden: isHidden,
      );
    }

    group('insert', () {
      test('should insert a workshop mod successfully', () async {
        final mod = createTestMod();

        final result = await repository.insert(mod);

        expect(result.isOk, isTrue);
        expect(result.value, equals(mod));

        final maps =
            await db.query('workshop_mods', where: 'id = ?', whereArgs: [mod.id]);
        expect(maps.length, equals(1));
        expect(maps.first['workshop_id'], equals('123456789'));
        expect(maps.first['title'], equals('Test Mod'));
      });

      test('should persist all optional fields', () async {
        final mod = createTestMod(
          fileSize: 2048,
          timeCreated: 1000,
          timeUpdated: 2000,
          subscriptions: 42,
          tags: ['ui', 'graphics'],
          lastCheckedAt: 3000,
          isHidden: true,
        );

        final result = await repository.insert(mod);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.isOk, isTrue);
        expect(getResult.value.fileSize, equals(2048));
        expect(getResult.value.timeCreated, equals(1000));
        expect(getResult.value.timeUpdated, equals(2000));
        expect(getResult.value.subscriptions, equals(42));
        expect(getResult.value.tags, equals(['ui', 'graphics']));
        expect(getResult.value.lastCheckedAt, equals(3000));
        expect(getResult.value.isHidden, isTrue);
      });

      test('should fail when inserting duplicate id', () async {
        final mod = createTestMod();
        await repository.insert(mod);

        final duplicate = createTestMod(workshopId: '999999999');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate workshop_id', () async {
        final mod1 = createTestMod(id: 'm1', workshopId: 'shared-ws-id');
        await repository.insert(mod1);

        final mod2 = createTestMod(id: 'm2', workshopId: 'shared-ws-id');
        final result = await repository.insert(mod2);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return mod when found', () async {
        final mod = createTestMod();
        await repository.insert(mod);

        final result = await repository.getById(mod.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(mod.id));
        expect(result.value.workshopId, equals(mod.workshopId));
      });

      test('should return error when mod not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByWorkshopId', () {
      test('should return mod when workshop_id found', () async {
        final mod = createTestMod(workshopId: 'ws-abc');
        await repository.insert(mod);

        final result = await repository.getByWorkshopId('ws-abc');

        expect(result.isOk, isTrue);
        expect(result.value.workshopId, equals('ws-abc'));
      });

      test('should return error when workshop_id not found', () async {
        final result = await repository.getByWorkshopId('missing-ws');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByWorkshopIds', () {
      test('should return matching mods for given workshop ids', () async {
        await repository.insert(createTestMod(id: 'm1', workshopId: 'w1'));
        await repository.insert(createTestMod(id: 'm2', workshopId: 'w2'));
        await repository.insert(createTestMod(id: 'm3', workshopId: 'w3'));

        final result = await repository.getByWorkshopIds(['w1', 'w3']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        final ids = result.value.map((m) => m.workshopId).toSet();
        expect(ids, equals({'w1', 'w3'}));
      });

      test('should return empty list when ids list is empty', () async {
        await repository.insert(createTestMod(id: 'm1', workshopId: 'w1'));

        final result = await repository.getByWorkshopIds([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return empty list when no ids match', () async {
        await repository.insert(createTestMod(id: 'm1', workshopId: 'w1'));

        final result = await repository.getByWorkshopIds(['nope1', 'nope2']);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getAll', () {
      test('should return empty list when no mods exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all mods ordered by time_updated DESC', () async {
        await repository
            .insert(createTestMod(id: 'm1', workshopId: 'w1', timeUpdated: 100));
        await repository
            .insert(createTestMod(id: 'm2', workshopId: 'w2', timeUpdated: 300));
        await repository
            .insert(createTestMod(id: 'm3', workshopId: 'w3', timeUpdated: 200));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('m2'));
        expect(result.value[1].id, equals('m3'));
        expect(result.value[2].id, equals('m1'));
      });
    });

    group('getByAppId', () {
      test('should return only mods for the given app id', () async {
        await repository
            .insert(createTestMod(id: 'm1', workshopId: 'w1', appId: 594570));
        await repository
            .insert(createTestMod(id: 'm2', workshopId: 'w2', appId: 594570));
        await repository
            .insert(createTestMod(id: 'm3', workshopId: 'w3', appId: 364360));

        final result = await repository.getByAppId(594570);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((m) => m.appId == 594570), isTrue);
      });

      test('should order results by time_updated DESC', () async {
        await repository.insert(
            createTestMod(id: 'm1', workshopId: 'w1', appId: 1, timeUpdated: 50));
        await repository.insert(
            createTestMod(id: 'm2', workshopId: 'w2', appId: 1, timeUpdated: 90));

        final result = await repository.getByAppId(1);

        expect(result.isOk, isTrue);
        expect(result.value[0].id, equals('m2'));
        expect(result.value[1].id, equals('m1'));
      });

      test('should return empty list when no mods for app id', () async {
        await repository
            .insert(createTestMod(id: 'm1', workshopId: 'w1', appId: 594570));

        final result = await repository.getByAppId(999999);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('upsert', () {
      test('should insert when workshop mod does not exist', () async {
        final mod = createTestMod();

        final result = await repository.upsert(mod);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.isOk, isTrue);
      });

      test('should replace existing mod with same id', () async {
        final mod = createTestMod(title: 'Original Title');
        await repository.insert(mod);

        final updated = mod.copyWith(title: 'New Title', subscriptions: 99);
        final result = await repository.upsert(updated);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.value.title, equals('New Title'));
        expect(getResult.value.subscriptions, equals(99));
      });
    });

    group('upsertBatch', () {
      test('should return empty list (Ok) for empty input', () async {
        final result = await repository.upsertBatch([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should insert all mods in a batch', () async {
        final mods = [
          createTestMod(id: 'm1', workshopId: 'w1'),
          createTestMod(id: 'm2', workshopId: 'w2'),
          createTestMod(id: 'm3', workshopId: 'w3'),
        ];

        final result = await repository.upsertBatch(mods);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));

        final all = await repository.getAll();
        expect(all.value.length, equals(3));
      });

      test('should replace existing mods on conflict within batch', () async {
        await repository
            .insert(createTestMod(id: 'm1', workshopId: 'w1', title: 'Old'));

        final mods = [
          createTestMod(id: 'm1', workshopId: 'w1', title: 'Updated'),
          createTestMod(id: 'm2', workshopId: 'w2', title: 'Fresh'),
        ];

        final result = await repository.upsertBatch(mods);
        expect(result.isOk, isTrue);

        final all = await repository.getAll();
        expect(all.value.length, equals(2));
        final m1 = await repository.getById('m1');
        expect(m1.value.title, equals('Updated'));
      });
    });

    group('update', () {
      test('should update mod successfully', () async {
        final mod = createTestMod(title: 'Before');
        await repository.insert(mod);

        // Bump updated_at so the updated_at-reset trigger does not interfere.
        final updated =
            mod.copyWith(title: 'After', updatedAt: mod.updatedAt + 10);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.title, equals('After'));

        final getResult = await repository.getById(mod.id);
        expect(getResult.value.title, equals('After'));
      });

      test('should return error when mod not found', () async {
        final mod = createTestMod(id: 'non-existent');

        final result = await repository.update(mod);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete mod successfully', () async {
        final mod = createTestMod();
        await repository.insert(mod);

        final result = await repository.delete(mod.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when mod not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('deleteByWorkshopId', () {
      test('should delete mod by workshop_id', () async {
        final mod = createTestMod(workshopId: 'del-ws');
        await repository.insert(mod);

        final result = await repository.deleteByWorkshopId('del-ws');

        expect(result.isOk, isTrue);

        final getResult = await repository.getByWorkshopId('del-ws');
        expect(getResult.isErr, isTrue);
      });

      test('should succeed (no-op) when workshop_id does not exist', () async {
        // delete() returns affected count 0 silently; no error expected.
        final result = await repository.deleteByWorkshopId('missing-ws');

        expect(result.isOk, isTrue);
      });
    });

    group('existsByWorkshopId', () {
      test('should return true when mod exists', () async {
        await repository.insert(createTestMod(workshopId: 'exists-ws'));

        final result = await repository.existsByWorkshopId('exists-ws');

        expect(result.isOk, isTrue);
        expect(result.value, isTrue);
      });

      test('should return false when mod does not exist', () async {
        final result = await repository.existsByWorkshopId('absent-ws');

        expect(result.isOk, isTrue);
        expect(result.value, isFalse);
      });
    });

    group('updateLastChecked', () {
      test('should update last_checked_at and updated_at', () async {
        final mod = createTestMod(
            workshopId: 'lc-ws',
            lastCheckedAt: null,
            createdAt: 1000,
            updatedAt: 1000);
        await repository.insert(mod);

        final result = await repository.updateLastChecked('lc-ws', 5000);

        expect(result.isOk, isTrue);

        final getResult = await repository.getByWorkshopId('lc-ws');
        expect(getResult.value.lastCheckedAt, equals(5000));
        expect(getResult.value.updatedAt, equals(5000));
      });

      test('should be a no-op when workshop_id not found', () async {
        final result = await repository.updateLastChecked('nope-ws', 5000);

        // database.update with no matching rows returns 0 but no exception.
        expect(result.isOk, isTrue);
      });
    });

    group('updateTimeUpdated', () {
      test('should update time_updated and bump updated_at', () async {
        final mod = createTestMod(workshopId: 'tu-ws', timeUpdated: 100);
        await repository.insert(mod);

        final result = await repository.updateTimeUpdated('tu-ws', 9999);

        expect(result.isOk, isTrue);

        final getResult = await repository.getByWorkshopId('tu-ws');
        expect(getResult.value.timeUpdated, equals(9999));
      });

      test('should be a no-op when workshop_id not found', () async {
        final result = await repository.updateTimeUpdated('nope-ws', 9999);

        expect(result.isOk, isTrue);
      });
    });

    group('getModsNeedingUpdateCheck', () {
      test('should include mods with null last_checked_at', () async {
        await repository.insert(createTestMod(
            id: 'm1', workshopId: 'w1', lastCheckedAt: null));

        final result = await repository.getModsNeedingUpdateCheck(3600);

        expect(result.isOk, isTrue);
        expect(result.value.map((m) => m.id), contains('m1'));
      });

      test('should include mods checked before the threshold', () async {
        final old = nowSeconds - 100000; // well beyond a 3600s threshold
        await repository.insert(createTestMod(
            id: 'stale', workshopId: 'w-stale', lastCheckedAt: old));

        final result = await repository.getModsNeedingUpdateCheck(3600);

        expect(result.isOk, isTrue);
        expect(result.value.map((m) => m.id), contains('stale'));
      });

      test('should exclude mods checked within the threshold', () async {
        final recent = nowSeconds - 10; // within 3600s window
        await repository.insert(createTestMod(
            id: 'fresh', workshopId: 'w-fresh', lastCheckedAt: recent));

        final result = await repository.getModsNeedingUpdateCheck(3600);

        expect(result.isOk, isTrue);
        expect(result.value.map((m) => m.id), isNot(contains('fresh')));
      });

      test('should order by last_checked_at ASC (nulls first)', () async {
        await repository.insert(createTestMod(
            id: 'with-ts',
            workshopId: 'w-ts',
            lastCheckedAt: nowSeconds - 100000));
        await repository.insert(createTestMod(
            id: 'null-ts', workshopId: 'w-null', lastCheckedAt: null));

        final result = await repository.getModsNeedingUpdateCheck(3600);

        expect(result.isOk, isTrue);
        // SQLite sorts NULL before non-null in ASC order.
        expect(result.value.first.id, equals('null-ts'));
      });

      test('should return empty list when nothing needs checking', () async {
        await repository.insert(createTestMod(
            id: 'fresh',
            workshopId: 'w-fresh',
            lastCheckedAt: nowSeconds - 5));

        final result = await repository.getModsNeedingUpdateCheck(3600);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('setHidden', () {
      test('should mark a mod as hidden', () async {
        final mod = createTestMod(workshopId: 'h-ws', isHidden: false);
        await repository.insert(mod);

        final result = await repository.setHidden('h-ws', true);

        expect(result.isOk, isTrue);

        final getResult = await repository.getByWorkshopId('h-ws');
        expect(getResult.value.isHidden, isTrue);
      });

      test('should unhide a previously hidden mod', () async {
        final mod = createTestMod(workshopId: 'h-ws', isHidden: true);
        await repository.insert(mod);

        final result = await repository.setHidden('h-ws', false);

        expect(result.isOk, isTrue);

        final getResult = await repository.getByWorkshopId('h-ws');
        expect(getResult.value.isHidden, isFalse);
      });

      test('should be a no-op when workshop_id not found', () async {
        final result = await repository.setHidden('nope-ws', true);

        expect(result.isOk, isTrue);
      });
    });

    group('getHiddenWorkshopIds', () {
      test('should return only hidden workshop ids', () async {
        await repository.insert(
            createTestMod(id: 'm1', workshopId: 'w1', isHidden: true));
        await repository.insert(
            createTestMod(id: 'm2', workshopId: 'w2', isHidden: false));
        await repository.insert(
            createTestMod(id: 'm3', workshopId: 'w3', isHidden: true));

        final result = await repository.getHiddenWorkshopIds();

        expect(result.isOk, isTrue);
        expect(result.value, equals({'w1', 'w3'}));
      });

      test('should return empty set when no mods are hidden', () async {
        await repository.insert(
            createTestMod(id: 'm1', workshopId: 'w1', isHidden: false));

        final result = await repository.getHiddenWorkshopIds();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('edge cases', () {
      test('should round-trip null optional fields', () async {
        final mod = createTestMod(
          fileSize: null,
          timeCreated: null,
          timeUpdated: null,
          subscriptions: null,
          tags: null,
          lastCheckedAt: null,
        );

        final result = await repository.insert(mod);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.value.fileSize, isNull);
        expect(getResult.value.timeCreated, isNull);
        expect(getResult.value.timeUpdated, isNull);
        expect(getResult.value.subscriptions, isNull);
        expect(getResult.value.tags, isNull);
        expect(getResult.value.lastCheckedAt, isNull);
      });

      test('should round-trip an empty tags list as empty list', () async {
        final mod = createTestMod(tags: <String>[]);

        final result = await repository.insert(mod);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.value.tags, isEmpty);
      });

      test('should handle unicode in title', () async {
        final mod = createTestMod(
          title: '中文 日本語 한국어',
        );

        final result = await repository.insert(mod);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(mod.id);
        expect(getResult.value.title,
            equals('中文 日本語 한국어'));
      });
    });
  });
}
