import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/mod_version.dart';
import 'package:twmt/repositories/mod_version_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ModVersionRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = ModVersionRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ModVersionRepository', () {
    // Use small base timestamps to respect any CHECK constraints; the
    // mod_versions table only constrains is_current IN (0, 1), but we keep
    // detected_at small and consistent for deterministic ordering.
    ModVersion createTestVersion({
      String? id,
      String? projectId,
      String? versionString,
      int? releaseDate,
      int? steamUpdateTimestamp,
      int unitsAdded = 0,
      int unitsModified = 0,
      int unitsDeleted = 0,
      bool isCurrent = true,
      int detectedAt = 1000,
    }) {
      return ModVersion(
        id: id ?? 'version-id',
        projectId: projectId ?? 'project-1',
        versionString: versionString ?? '1.0.0',
        releaseDate: releaseDate,
        steamUpdateTimestamp: steamUpdateTimestamp,
        unitsAdded: unitsAdded,
        unitsModified: unitsModified,
        unitsDeleted: unitsDeleted,
        isCurrent: isCurrent,
        detectedAt: detectedAt,
      );
    }

    group('insert', () {
      test('should insert a mod version successfully', () async {
        final version = createTestVersion();

        final result = await repository.insert(version);

        expect(result.isOk, isTrue);
        expect(result.value, equals(version));

        final maps =
            await db.query('mod_versions', where: 'id = ?', whereArgs: [version.id]);
        expect(maps.length, equals(1));
        expect(maps.first['version_string'], equals('1.0.0'));
        expect(maps.first['is_current'], equals(1));
      });

      test('should persist is_current as 0 when not current', () async {
        final version = createTestVersion(isCurrent: false);

        final result = await repository.insert(version);

        expect(result.isOk, isTrue);
        final maps =
            await db.query('mod_versions', where: 'id = ?', whereArgs: [version.id]);
        expect(maps.first['is_current'], equals(0));
      });

      test('should fail when inserting duplicate ID', () async {
        final version = createTestVersion();
        await repository.insert(version);

        final duplicate = createTestVersion(versionString: '2.0.0');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return version when found', () async {
        final version = createTestVersion(
          releaseDate: 5000,
          steamUpdateTimestamp: 6000,
          unitsAdded: 3,
          unitsModified: 2,
          unitsDeleted: 1,
        );
        await repository.insert(version);

        final result = await repository.getById(version.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(version.id));
        expect(result.value.versionString, equals('1.0.0'));
        expect(result.value.releaseDate, equals(5000));
        expect(result.value.steamUpdateTimestamp, equals(6000));
        expect(result.value.unitsAdded, equals(3));
        expect(result.value.unitsModified, equals(2));
        expect(result.value.unitsDeleted, equals(1));
      });

      test('should return error when version not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no versions exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all versions ordered by detected_at DESC', () async {
        await repository.insert(createTestVersion(
          id: 'v1',
          versionString: '1.0.0',
          detectedAt: 1000,
          isCurrent: false,
        ));
        await repository.insert(createTestVersion(
          id: 'v2',
          versionString: '2.0.0',
          detectedAt: 3000,
          isCurrent: false,
        ));
        await repository.insert(createTestVersion(
          id: 'v3',
          versionString: '3.0.0',
          detectedAt: 2000,
          isCurrent: false,
        ));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        // Newest detected_at first.
        expect(result.value[0].id, equals('v2'));
        expect(result.value[1].id, equals('v3'));
        expect(result.value[2].id, equals('v1'));
      });
    });

    group('update', () {
      test('should update version successfully', () async {
        final version = createTestVersion();
        await repository.insert(version);

        final updated = version.copyWith(versionString: '1.1.0', unitsAdded: 10);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.versionString, equals('1.1.0'));
        expect(result.value.unitsAdded, equals(10));

        final getResult = await repository.getById(version.id);
        expect(getResult.value.versionString, equals('1.1.0'));
        expect(getResult.value.unitsAdded, equals(10));
      });

      test('should return error when version not found', () async {
        final version = createTestVersion(id: 'non-existent');

        final result = await repository.update(version);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete version successfully', () async {
        final version = createTestVersion();
        await repository.insert(version);

        final result = await repository.delete(version.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(version.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when version not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByProject', () {
      test('should return versions only for the given project, '
          'ordered by detected_at DESC', () async {
        await repository.insert(createTestVersion(
          id: 'a1',
          projectId: 'project-A',
          detectedAt: 1000,
          isCurrent: false,
        ));
        await repository.insert(createTestVersion(
          id: 'a2',
          projectId: 'project-A',
          detectedAt: 2000,
          isCurrent: false,
        ));
        await repository.insert(createTestVersion(
          id: 'b1',
          projectId: 'project-B',
          detectedAt: 3000,
          isCurrent: false,
        ));

        final result = await repository.getByProject('project-A');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('a2')); // newest first
        expect(result.value[1].id, equals('a1'));
      });

      test('should return empty list when project has no versions', () async {
        await repository.insert(createTestVersion(
          id: 'x1',
          projectId: 'project-X',
          isCurrent: false,
        ));

        final result = await repository.getByProject('project-without-versions');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getCurrent', () {
      test('should return the current version for a project', () async {
        await repository.insert(createTestVersion(
          id: 'old',
          projectId: 'project-1',
          versionString: '1.0.0',
          detectedAt: 1000,
          isCurrent: false,
        ));
        await repository.insert(createTestVersion(
          id: 'cur',
          projectId: 'project-1',
          versionString: '2.0.0',
          detectedAt: 2000,
          isCurrent: true,
        ));

        final result = await repository.getCurrent('project-1');

        expect(result.isOk, isTrue);
        expect(result.value.id, equals('cur'));
        expect(result.value.isCurrent, isTrue);
        expect(result.value.versionString, equals('2.0.0'));
      });

      test('should return error when project has no current version', () async {
        await repository.insert(createTestVersion(
          id: 'noncurrent',
          projectId: 'project-1',
          isCurrent: false,
        ));

        final result = await repository.getCurrent('project-1');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });

      test('should return error when project does not exist', () async {
        final result = await repository.getCurrent('unknown-project');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('markAsCurrent', () {
      test('should mark a version as current and unmark siblings '
          'in the same project', () async {
        await repository.insert(createTestVersion(
          id: 'v1',
          projectId: 'project-1',
          detectedAt: 1000,
          isCurrent: true,
        ));
        await repository.insert(createTestVersion(
          id: 'v2',
          projectId: 'project-1',
          detectedAt: 2000,
          isCurrent: false,
        ));

        final result = await repository.markAsCurrent('v2');

        expect(result.isOk, isTrue);
        expect(result.value.id, equals('v2'));
        expect(result.value.isCurrent, isTrue);

        // v1 should now be unmarked.
        final v1 = await repository.getById('v1');
        expect(v1.value.isCurrent, isFalse);

        // Exactly one current version for the project.
        final current = await repository.getCurrent('project-1');
        expect(current.value.id, equals('v2'));
      });

      test('should not affect versions in other projects', () async {
        await repository.insert(createTestVersion(
          id: 'p1v1',
          projectId: 'project-1',
          isCurrent: true,
        ));
        await repository.insert(createTestVersion(
          id: 'p2v1',
          projectId: 'project-2',
          isCurrent: true,
        ));
        await repository.insert(createTestVersion(
          id: 'p1v2',
          projectId: 'project-1',
          detectedAt: 2000,
          isCurrent: false,
        ));

        final result = await repository.markAsCurrent('p1v2');

        expect(result.isOk, isTrue);

        // project-2's current version is untouched.
        final p2Current = await repository.getCurrent('project-2');
        expect(p2Current.value.id, equals('p2v1'));
        expect(p2Current.value.isCurrent, isTrue);
      });

      test('should return error when version not found', () async {
        final result = await repository.markAsCurrent('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });
  });
}
