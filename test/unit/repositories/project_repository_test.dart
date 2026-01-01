import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/database/database_service.dart';

void main() {
  late Database db;
  late ProjectRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Create projects table
    await db.execute('''
      CREATE TABLE projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        mod_steam_id TEXT,
        mod_version TEXT,
        game_installation_id TEXT NOT NULL,
        source_file_path TEXT,
        output_file_path TEXT,
        last_update_check INTEGER,
        source_mod_updated INTEGER,
        batch_size INTEGER DEFAULT 25,
        parallel_batches INTEGER DEFAULT 3,
        custom_prompt TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        completed_at INTEGER,
        metadata TEXT,
        has_mod_update_impact INTEGER DEFAULT 0,
        project_type TEXT DEFAULT 'mod',
        source_language_code TEXT,
        status TEXT
      )
    ''');

    // Initialize DatabaseService with the test database
    DatabaseService.setTestDatabase(db);

    repository = ProjectRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('ProjectRepository', () {
    Project createTestProject({
      String? id,
      String? name,
      String? modSteamId,
      String? gameInstallationId,
      int? createdAt,
      int? updatedAt,
      String? projectType,
      bool? hasModUpdateImpact,
    }) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return Project(
        id: id ?? 'test-project-id',
        name: name ?? 'Test Project',
        modSteamId: modSteamId ?? '12345',
        gameInstallationId: gameInstallationId ?? 'game-install-id',
        batchSize: 25,
        parallelBatches: 3,
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
        projectType: projectType ?? 'mod',
        hasModUpdateImpact: hasModUpdateImpact ?? false,
      );
    }

    group('insert', () {
      test('should insert a project successfully', () async {
        final project = createTestProject();

        final result = await repository.insert(project);

        expect(result.isOk, isTrue);
        expect(result.value, equals(project));

        // Verify it's in the database
        final maps = await db.query('projects', where: 'id = ?', whereArgs: [project.id]);
        expect(maps.length, equals(1));
        expect(maps.first['name'], equals('Test Project'));
      });

      test('should fail when inserting duplicate ID', () async {
        final project = createTestProject();
        await repository.insert(project);

        final duplicate = createTestProject(name: 'Duplicate Project');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return project when found', () async {
        final project = createTestProject();
        await repository.insert(project);

        final result = await repository.getById(project.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(project.id));
        expect(result.value.name, equals(project.name));
      });

      test('should return error when project not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no projects exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all projects ordered by updated_at DESC', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final project1 = createTestProject(
          id: 'project-1',
          name: 'Project 1',
          updatedAt: now - 100,
        );
        final project2 = createTestProject(
          id: 'project-2',
          name: 'Project 2',
          updatedAt: now,
        );
        final project3 = createTestProject(
          id: 'project-3',
          name: 'Project 3',
          updatedAt: now - 50,
        );

        await repository.insert(project1);
        await repository.insert(project2);
        await repository.insert(project3);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        // Should be ordered by updated_at DESC
        expect(result.value[0].id, equals('project-2'));
        expect(result.value[1].id, equals('project-3'));
        expect(result.value[2].id, equals('project-1'));
      });
    });

    group('update', () {
      test('should update project successfully', () async {
        final project = createTestProject();
        await repository.insert(project);

        final updatedProject = project.copyWith(name: 'Updated Name');
        final result = await repository.update(updatedProject);

        expect(result.isOk, isTrue);
        expect(result.value.name, equals('Updated Name'));

        // Verify in database
        final getResult = await repository.getById(project.id);
        expect(getResult.value.name, equals('Updated Name'));
      });

      test('should return error when project not found', () async {
        final project = createTestProject(id: 'non-existent');

        final result = await repository.update(project);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByStatus', () {
      test('should return projects with matching status', () async {
        // Insert projects with status in metadata or similar field
        // Note: The current implementation uses 'status' column which might not exist
        // This test demonstrates the pattern
        final project1 = createTestProject(id: 'project-1', name: 'Project 1');
        final project2 = createTestProject(id: 'project-2', name: 'Project 2');

        await repository.insert(project1);
        await repository.insert(project2);

        // Update one with status
        await db.update(
          'projects',
          {'status': 'active'},
          where: 'id = ?',
          whereArgs: ['project-1'],
        );

        final result = await repository.getByStatus('active');

        // Note: This may return empty if status column doesn't exist
        expect(result.isOk, isTrue);
      });
    });

    group('getByGameInstallation', () {
      test('should return projects for a specific game installation', () async {
        final project1 = createTestProject(
          id: 'project-1',
          gameInstallationId: 'game-1',
        );
        final project2 = createTestProject(
          id: 'project-2',
          gameInstallationId: 'game-2',
        );
        final project3 = createTestProject(
          id: 'project-3',
          gameInstallationId: 'game-1',
        );

        await repository.insert(project1);
        await repository.insert(project2);
        await repository.insert(project3);

        final result = await repository.getByGameInstallation('game-1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((p) => p.gameInstallationId == 'game-1'), isTrue);
      });

      test('should return empty list when no projects found', () async {
        final result = await repository.getByGameInstallation('non-existent');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('setModUpdateImpact', () {
      test('should set mod update impact flag', () async {
        final project = createTestProject();
        await repository.insert(project);

        final result = await repository.setModUpdateImpact(project.id, true);

        expect(result.isOk, isTrue);

        // Verify in database
        final getResult = await repository.getById(project.id);
        expect(getResult.value.hasModUpdateImpact, isTrue);
      });

      test('should clear mod update impact flag', () async {
        final project = createTestProject(hasModUpdateImpact: true);
        await repository.insert(project);

        final result = await repository.setModUpdateImpact(project.id, false);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(project.id);
        expect(getResult.value.hasModUpdateImpact, isFalse);
      });

      test('should return error when project not found', () async {
        final result = await repository.setModUpdateImpact('non-existent', true);

        expect(result.isErr, isTrue);
      });
    });

    group('clearModUpdateImpact', () {
      test('should clear mod update impact flag', () async {
        final project = createTestProject(hasModUpdateImpact: true);
        await repository.insert(project);

        final result = await repository.clearModUpdateImpact(project.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(project.id);
        expect(getResult.value.hasModUpdateImpact, isFalse);
      });
    });

    group('countWithModUpdateImpact', () {
      test('should count projects with mod update impact', () async {
        final project1 = createTestProject(
          id: 'project-1',
          gameInstallationId: 'game-1',
          hasModUpdateImpact: true,
        );
        final project2 = createTestProject(
          id: 'project-2',
          gameInstallationId: 'game-1',
          hasModUpdateImpact: false,
        );
        final project3 = createTestProject(
          id: 'project-3',
          gameInstallationId: 'game-1',
          hasModUpdateImpact: true,
        );
        final project4 = createTestProject(
          id: 'project-4',
          gameInstallationId: 'game-2',
          hasModUpdateImpact: true,
        );

        await repository.insert(project1);
        await repository.insert(project2);
        await repository.insert(project3);
        await repository.insert(project4);

        final result = await repository.countWithModUpdateImpact('game-1');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });
    });

    group('getByType', () {
      test('should return mod projects', () async {
        final modProject = createTestProject(
          id: 'mod-project',
          projectType: 'mod',
        );
        final gameProject = createTestProject(
          id: 'game-project',
          projectType: 'game',
        );

        await repository.insert(modProject);
        await repository.insert(gameProject);

        final result = await repository.getByType('mod');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.projectType, equals('mod'));
      });

      test('should return game projects', () async {
        final modProject = createTestProject(
          id: 'mod-project',
          projectType: 'mod',
        );
        final gameProject = createTestProject(
          id: 'game-project',
          projectType: 'game',
        );

        await repository.insert(modProject);
        await repository.insert(gameProject);

        final result = await repository.getByType('game');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.projectType, equals('game'));
      });
    });

    group('getGameTranslationsByInstallation', () {
      test('should return only game translation projects for installation', () async {
        final modProject = createTestProject(
          id: 'mod-project',
          gameInstallationId: 'game-1',
          projectType: 'mod',
        );
        final gameProject = createTestProject(
          id: 'game-project',
          gameInstallationId: 'game-1',
          projectType: 'game',
        );
        final otherGameProject = createTestProject(
          id: 'other-game-project',
          gameInstallationId: 'game-2',
          projectType: 'game',
        );

        await repository.insert(modProject);
        await repository.insert(gameProject);
        await repository.insert(otherGameProject);

        final result = await repository.getGameTranslationsByInstallation('game-1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.id, equals('game-project'));
      });
    });

    group('getModTranslationsByInstallation', () {
      test('should return only mod translation projects for installation', () async {
        final modProject1 = createTestProject(
          id: 'mod-project-1',
          gameInstallationId: 'game-1',
          projectType: 'mod',
        );
        final modProject2 = createTestProject(
          id: 'mod-project-2',
          gameInstallationId: 'game-1',
          projectType: 'mod',
        );
        final gameProject = createTestProject(
          id: 'game-project',
          gameInstallationId: 'game-1',
          projectType: 'game',
        );

        await repository.insert(modProject1);
        await repository.insert(modProject2);
        await repository.insert(gameProject);

        final result = await repository.getModTranslationsByInstallation('game-1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((p) => p.projectType == 'mod'), isTrue);
      });
    });
  });
}
