import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/repositories/compilation_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late CompilationRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = CompilationRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('CompilationRepository', () {
    final baseNow = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Compilation createTestCompilation({
      String? id,
      String? name,
      String? prefix,
      String? packName,
      String? gameInstallationId,
      String? languageId,
      String? lastOutputPath,
      int? lastGeneratedAt,
      String? publishedSteamId,
      int? publishedAt,
      int? createdAt,
      int? updatedAt,
    }) {
      return Compilation(
        id: id ?? 'comp-id',
        name: name ?? 'Test Compilation',
        prefix: prefix ?? '!!!!!!!!!!_fr_compilation_twmt_',
        packName: packName ?? 'my_translations',
        gameInstallationId: gameInstallationId ?? 'game-1',
        languageId: languageId,
        lastOutputPath: lastOutputPath,
        lastGeneratedAt: lastGeneratedAt,
        publishedSteamId: publishedSteamId,
        publishedAt: publishedAt,
        createdAt: createdAt ?? baseNow,
        updatedAt: updatedAt ?? baseNow,
      );
    }

    group('insert', () {
      test('should insert a compilation successfully', () async {
        final compilation = createTestCompilation();

        final result = await repository.insert(compilation);

        expect(result.isOk, isTrue);
        expect(result.value, equals(compilation));

        final maps =
            await db.query('compilations', where: 'id = ?', whereArgs: [compilation.id]);
        expect(maps.length, equals(1));
        expect(maps.first['name'], equals('Test Compilation'));
        expect(maps.first['pack_name'], equals('my_translations'));
      });

      test('should fail when inserting duplicate ID', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final duplicate = createTestCompilation(name: 'Different Name');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should persist all optional fields', () async {
        final compilation = createTestCompilation(
          id: 'full-comp',
          languageId: 'lang-fr',
          lastOutputPath: '/path/to/out.pack',
          lastGeneratedAt: baseNow,
          publishedSteamId: 'steam-123',
          publishedAt: baseNow,
        );

        final result = await repository.insert(compilation);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('full-comp');
        expect(getResult.isOk, isTrue);
        expect(getResult.value.languageId, equals('lang-fr'));
        expect(getResult.value.lastOutputPath, equals('/path/to/out.pack'));
        expect(getResult.value.lastGeneratedAt, equals(baseNow));
        expect(getResult.value.publishedSteamId, equals('steam-123'));
        expect(getResult.value.publishedAt, equals(baseNow));
      });
    });

    group('getById', () {
      test('should return compilation when found', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result = await repository.getById(compilation.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(compilation.id));
        expect(result.value.name, equals(compilation.name));
      });

      test('should return error when compilation not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no compilations exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all compilations ordered by updated_at DESC', () async {
        await repository.insert(createTestCompilation(
            id: 'c1', name: 'Old', createdAt: baseNow, updatedAt: baseNow));
        await repository.insert(createTestCompilation(
            id: 'c2', name: 'New', createdAt: baseNow, updatedAt: baseNow + 100));
        await repository.insert(createTestCompilation(
            id: 'c3', name: 'Mid', createdAt: baseNow, updatedAt: baseNow + 50));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('c2'));
        expect(result.value[1].id, equals('c3'));
        expect(result.value[2].id, equals('c1'));
      });
    });

    group('update', () {
      test('should update compilation successfully', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final updated = compilation.copyWith(name: 'Renamed', updatedAt: baseNow + 10);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.name, equals('Renamed'));

        final getResult = await repository.getById(compilation.id);
        expect(getResult.value.name, equals('Renamed'));
      });

      test('should return error when compilation not found', () async {
        final compilation = createTestCompilation(id: 'non-existent');

        final result = await repository.update(compilation);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete compilation successfully', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result = await repository.delete(compilation.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(compilation.id);
        expect(getResult.isErr, isTrue);
      });

      test('should succeed (no error) when deleting non-existent id', () async {
        final result = await repository.delete('non-existent-id');

        // delete() does not assert rowsAffected, so it succeeds silently.
        expect(result.isOk, isTrue);
      });
    });

    group('getByGameInstallation', () {
      test('should return only compilations for the given installation', () async {
        await repository.insert(createTestCompilation(
            id: 'g1a', gameInstallationId: 'game-A', updatedAt: baseNow + 10));
        await repository.insert(createTestCompilation(
            id: 'g1b', gameInstallationId: 'game-A', updatedAt: baseNow + 20));
        await repository.insert(createTestCompilation(
            id: 'g2a', gameInstallationId: 'game-B'));

        final result = await repository.getByGameInstallation('game-A');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((c) => c.gameInstallationId == 'game-A'), isTrue);
        // Ordered by updated_at DESC
        expect(result.value[0].id, equals('g1b'));
        expect(result.value[1].id, equals('g1a'));
      });

      test('should return empty list when no compilation matches', () async {
        await repository.insert(createTestCompilation(gameInstallationId: 'game-A'));

        final result = await repository.getByGameInstallation('game-unknown');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('addProject', () {
      test('should add a project and assign sort_order 0 for first', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result = await repository.addProject(compilation.id, 'proj-1');

        expect(result.isOk, isTrue);
        expect(result.value.compilationId, equals(compilation.id));
        expect(result.value.projectId, equals('proj-1'));
        expect(result.value.sortOrder, equals(0));

        final rows = await db.query('compilation_projects',
            where: 'compilation_id = ?', whereArgs: [compilation.id]);
        expect(rows.length, equals(1));
      });

      test('should increment sort_order for subsequent projects', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final first = await repository.addProject(compilation.id, 'proj-1');
        final second = await repository.addProject(compilation.id, 'proj-2');
        final third = await repository.addProject(compilation.id, 'proj-3');

        expect(first.value.sortOrder, equals(0));
        expect(second.value.sortOrder, equals(1));
        expect(third.value.sortOrder, equals(2));
      });

      test('should bump the compilation updated_at timestamp', () async {
        final compilation =
            createTestCompilation(createdAt: 1000, updatedAt: baseNow);
        await repository.insert(compilation);

        // Force an older updated_at directly to observe the bump.
        // created_at is kept far in the past so the forced/old value stays
        // >= created_at and does not trip the CHECK (created_at <= updated_at).
        await db.update('compilations', {'updated_at': baseNow - 1000},
            where: 'id = ?', whereArgs: [compilation.id]);

        await repository.addProject(compilation.id, 'proj-1');

        final getResult = await repository.getById(compilation.id);
        expect(getResult.value.updatedAt, greaterThanOrEqualTo(baseNow));
      });

      test('should ignore duplicate (compilation_id, project_id) pair', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        await repository.addProject(compilation.id, 'proj-1');
        // ConflictAlgorithm.ignore: second add of the same pair is a no-op insert.
        final result = await repository.addProject(compilation.id, 'proj-1');

        expect(result.isOk, isTrue);

        final ids = await repository.getProjectIds(compilation.id);
        expect(ids.value.where((p) => p == 'proj-1').length, equals(1));
      });
    });

    group('getProjectIds', () {
      test('should return project ids ordered by sort_order ASC', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        await repository.addProject(compilation.id, 'proj-a');
        await repository.addProject(compilation.id, 'proj-b');
        await repository.addProject(compilation.id, 'proj-c');

        final result = await repository.getProjectIds(compilation.id);

        expect(result.isOk, isTrue);
        expect(result.value, equals(['proj-a', 'proj-b', 'proj-c']));
      });

      test('should return empty list when compilation has no projects', () async {
        final result = await repository.getProjectIds('comp-without-projects');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getCompilationProjects', () {
      test('should return full CompilationProject rows ordered by sort_order', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        await repository.addProject(compilation.id, 'proj-1');
        await repository.addProject(compilation.id, 'proj-2');

        final result = await repository.getCompilationProjects(compilation.id);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].projectId, equals('proj-1'));
        expect(result.value[0].sortOrder, equals(0));
        expect(result.value[1].projectId, equals('proj-2'));
        expect(result.value[1].sortOrder, equals(1));
        expect(result.value[0].compilationId, equals(compilation.id));
      });

      test('should return empty list when no projects', () async {
        final result = await repository.getCompilationProjects('nope');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('removeProject', () {
      test('should remove a project from a compilation', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        await repository.addProject(compilation.id, 'proj-1');
        await repository.addProject(compilation.id, 'proj-2');

        final result = await repository.removeProject(compilation.id, 'proj-1');

        expect(result.isOk, isTrue);

        final ids = await repository.getProjectIds(compilation.id);
        expect(ids.value, equals(['proj-2']));
      });

      test('should succeed even when project not present', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result = await repository.removeProject(compilation.id, 'never-added');

        expect(result.isOk, isTrue);
      });

      test('should bump the compilation updated_at timestamp', () async {
        final compilation = createTestCompilation(createdAt: 1000);
        await repository.insert(compilation);
        await repository.addProject(compilation.id, 'proj-1');

        await db.update('compilations', {'updated_at': baseNow - 1000},
            where: 'id = ?', whereArgs: [compilation.id]);

        await repository.removeProject(compilation.id, 'proj-1');

        final getResult = await repository.getById(compilation.id);
        expect(getResult.value.updatedAt, greaterThanOrEqualTo(baseNow));
      });
    });

    group('setProjects', () {
      test('should replace all existing projects with the new set', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        await repository.addProject(compilation.id, 'old-1');
        await repository.addProject(compilation.id, 'old-2');

        final result =
            await repository.setProjects(compilation.id, ['new-a', 'new-b', 'new-c']);

        expect(result.isOk, isTrue);

        final ids = await repository.getProjectIds(compilation.id);
        expect(ids.value, equals(['new-a', 'new-b', 'new-c']));
      });

      test('should assign sequential sort_order matching list order', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        await repository.setProjects(compilation.id, ['p0', 'p1', 'p2']);

        final projects = await repository.getCompilationProjects(compilation.id);
        expect(projects.value[0].sortOrder, equals(0));
        expect(projects.value[1].sortOrder, equals(1));
        expect(projects.value[2].sortOrder, equals(2));
      });

      test('should clear all projects when given an empty list', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);
        await repository.addProject(compilation.id, 'proj-1');

        final result = await repository.setProjects(compilation.id, []);

        expect(result.isOk, isTrue);

        final ids = await repository.getProjectIds(compilation.id);
        expect(ids.value, isEmpty);
      });

      test('should bump the compilation updated_at timestamp', () async {
        final compilation = createTestCompilation(createdAt: 1000);
        await repository.insert(compilation);

        await db.update('compilations', {'updated_at': baseNow - 1000},
            where: 'id = ?', whereArgs: [compilation.id]);

        await repository.setProjects(compilation.id, ['p0']);

        final getResult = await repository.getById(compilation.id);
        expect(getResult.value.updatedAt, greaterThanOrEqualTo(baseNow));
      });
    });

    group('updateAfterGeneration', () {
      test('should set output path and timestamps, returning the updated row',
          () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result =
            await repository.updateAfterGeneration(compilation.id, '/out/file.pack');

        expect(result.isOk, isTrue);
        expect(result.value.lastOutputPath, equals('/out/file.pack'));
        expect(result.value.lastGeneratedAt, isNotNull);
        expect(result.value.hasBeenGenerated, isTrue);
      });

      test('should error when compilation does not exist', () async {
        // The UPDATE affects 0 rows silently; the subsequent getById fails.
        final result =
            await repository.updateAfterGeneration('missing', '/out/file.pack');

        expect(result.isErr, isTrue);
      });
    });

    group('updateAfterPublish', () {
      test('should set published_steam_id and published_at', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result = await repository.updateAfterPublish(
            compilation.id, 'workshop-999', baseNow + 5);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(compilation.id);
        expect(getResult.value.publishedSteamId, equals('workshop-999'));
        expect(getResult.value.publishedAt, equals(baseNow + 5));
      });

      test('should error when compilation not found', () async {
        final result =
            await repository.updateAfterPublish('missing', 'workshop-1', baseNow);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('setWorkshopId', () {
      test('should set published_steam_id without touching published_at', () async {
        final compilation = createTestCompilation();
        await repository.insert(compilation);

        final result = await repository.setWorkshopId(compilation.id, 'ws-42');

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(compilation.id);
        expect(getResult.value.publishedSteamId, equals('ws-42'));
        // published_at must remain null (not set to 0) per the method contract.
        expect(getResult.value.publishedAt, isNull);
      });

      test('should error when compilation not found', () async {
        final result = await repository.setWorkshopId('missing', 'ws-1');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getCount', () {
      test('should return 0 when no compilations exist', () async {
        final result = await repository.getCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should return the number of compilations', () async {
        await repository.insert(createTestCompilation(id: 'c1'));
        await repository.insert(createTestCompilation(id: 'c2'));
        await repository.insert(createTestCompilation(id: 'c3'));

        final result = await repository.getCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(3));
      });
    });
  });
}
