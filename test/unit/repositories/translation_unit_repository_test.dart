import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/services/database/database_service.dart';

void main() {
  late Database db;
  late TranslationUnitRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Create translation_units table
    await db.execute('''
      CREATE TABLE translation_units (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        key TEXT NOT NULL,
        source_text TEXT NOT NULL,
        context TEXT,
        notes TEXT,
        source_loc_file TEXT,
        is_obsolete INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Create translation_versions table for join tests
    await db.execute('''
      CREATE TABLE translation_versions (
        id TEXT PRIMARY KEY,
        unit_id TEXT NOT NULL,
        project_language_id TEXT NOT NULL,
        translated_text TEXT,
        is_manually_edited INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending',
        translation_source TEXT,
        validation_issues TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (unit_id) REFERENCES translation_units(id) ON DELETE CASCADE
      )
    ''');

    // Initialize DatabaseService with the test database
    DatabaseService.setTestDatabase(db);

    repository = TranslationUnitRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('TranslationUnitRepository', () {
    TranslationUnit createTestUnit({
      String? id,
      String? projectId,
      String? key,
      String? sourceText,
      String? context,
      String? notes,
      String? sourceLocFile,
      bool? isObsolete,
      int? createdAt,
      int? updatedAt,
    }) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return TranslationUnit(
        id: id ?? 'unit-id',
        projectId: projectId ?? 'project-id',
        key: key ?? 'unit.key',
        sourceText: sourceText ?? 'Hello World',
        context: context,
        notes: notes,
        sourceLocFile: sourceLocFile,
        isObsolete: isObsolete ?? false,
        createdAt: createdAt ?? now,
        updatedAt: updatedAt ?? now,
      );
    }

    group('insert', () {
      test('should insert a translation unit successfully', () async {
        final unit = createTestUnit();

        final result = await repository.insert(unit);

        expect(result.isOk, isTrue);
        expect(result.value, equals(unit));

        // Verify it's in the database
        final maps = await db.query('translation_units', where: 'id = ?', whereArgs: [unit.id]);
        expect(maps.length, equals(1));
        expect(maps.first['key'], equals('unit.key'));
      });

      test('should fail when inserting duplicate ID', () async {
        final unit = createTestUnit();
        await repository.insert(unit);

        final duplicate = createTestUnit(key: 'different.key');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return unit when found', () async {
        final unit = createTestUnit();
        await repository.insert(unit);

        final result = await repository.getById(unit.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(unit.id));
        expect(result.value.key, equals(unit.key));
        expect(result.value.sourceText, equals(unit.sourceText));
      });

      test('should return error when unit not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no units exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all units ordered by created_at DESC', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final unit1 = createTestUnit(id: 'u1', createdAt: now - 100);
        final unit2 = createTestUnit(id: 'u2', createdAt: now);
        final unit3 = createTestUnit(id: 'u3', createdAt: now - 50);

        await repository.insert(unit1);
        await repository.insert(unit2);
        await repository.insert(unit3);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].id, equals('u2'));
        expect(result.value[1].id, equals('u3'));
        expect(result.value[2].id, equals('u1'));
      });
    });

    group('update', () {
      test('should update unit successfully', () async {
        final unit = createTestUnit();
        await repository.insert(unit);

        final updated = unit.copyWith(sourceText: 'Updated Text');
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.sourceText, equals('Updated Text'));

        // Verify in database
        final getResult = await repository.getById(unit.id);
        expect(getResult.value.sourceText, equals('Updated Text'));
      });

      test('should return error when unit not found', () async {
        final unit = createTestUnit(id: 'non-existent');

        final result = await repository.update(unit);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete unit successfully', () async {
        final unit = createTestUnit();
        await repository.insert(unit);

        final result = await repository.delete(unit.id);

        expect(result.isOk, isTrue);

        // Verify it's deleted
        final getResult = await repository.getById(unit.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when unit not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByProject', () {
      test('should return units for specific project', () async {
        final unit1 = createTestUnit(id: 'u1', projectId: 'project-1', key: 'a.key');
        final unit2 = createTestUnit(id: 'u2', projectId: 'project-1', key: 'b.key');
        final unit3 = createTestUnit(id: 'u3', projectId: 'project-2', key: 'c.key');

        await repository.insert(unit1);
        await repository.insert(unit2);
        await repository.insert(unit3);

        final result = await repository.getByProject('project-1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((u) => u.projectId == 'project-1'), isTrue);
      });

      test('should return units ordered by key ASC', () async {
        final unit1 = createTestUnit(id: 'u1', key: 'z.key');
        final unit2 = createTestUnit(id: 'u2', key: 'a.key');
        final unit3 = createTestUnit(id: 'u3', key: 'm.key');

        await repository.insert(unit1);
        await repository.insert(unit2);
        await repository.insert(unit3);

        final result = await repository.getByProject('project-id');

        expect(result.isOk, isTrue);
        expect(result.value[0].key, equals('a.key'));
        expect(result.value[1].key, equals('m.key'));
        expect(result.value[2].key, equals('z.key'));
      });

      test('should return empty list when no units for project', () async {
        final result = await repository.getByProject('non-existent-project');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getByKey', () {
      test('should return unit when project and key match', () async {
        final unit = createTestUnit(projectId: 'project-1', key: 'unique.key');
        await repository.insert(unit);

        final result = await repository.getByKey('project-1', 'unique.key');

        expect(result.isOk, isTrue);
        expect(result.value.key, equals('unique.key'));
      });

      test('should return error when key not found', () async {
        final result = await repository.getByKey('project-1', 'non.existent.key');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });

      test('should not find key from different project', () async {
        final unit = createTestUnit(projectId: 'project-1', key: 'shared.key');
        await repository.insert(unit);

        final result = await repository.getByKey('project-2', 'shared.key');

        expect(result.isErr, isTrue);
      });
    });

    group('markObsolete', () {
      test('should mark unit as obsolete', () async {
        final unit = createTestUnit(isObsolete: false);
        await repository.insert(unit);

        final result = await repository.markObsolete(unit.id);

        expect(result.isOk, isTrue);
        expect(result.value.isObsolete, isTrue);
      });

      test('should return error when unit not found', () async {
        final result = await repository.markObsolete('non-existent');

        expect(result.isErr, isTrue);
      });

      test('should update the updated_at timestamp', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final unit = createTestUnit(updatedAt: now - 1000);
        await repository.insert(unit);

        await Future.delayed(const Duration(milliseconds: 100));

        final result = await repository.markObsolete(unit.id);

        expect(result.value.updatedAt, greaterThanOrEqualTo(now));
      });
    });

    group('getActive', () {
      test('should return only non-obsolete units', () async {
        final active1 = createTestUnit(id: 'a1', isObsolete: false);
        final active2 = createTestUnit(id: 'a2', isObsolete: false);
        final obsolete = createTestUnit(id: 'o1', isObsolete: true);

        await repository.insert(active1);
        await repository.insert(active2);
        await repository.insert(obsolete);

        final result = await repository.getActive('project-id');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((u) => !u.isObsolete), isTrue);
      });

      test('should filter by project', () async {
        final active1 = createTestUnit(id: 'a1', projectId: 'p1', isObsolete: false);
        final active2 = createTestUnit(id: 'a2', projectId: 'p2', isObsolete: false);

        await repository.insert(active1);
        await repository.insert(active2);

        final result = await repository.getActive('p1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.projectId, equals('p1'));
      });
    });

    group('getObsolete', () {
      test('should return only obsolete units', () async {
        final active = createTestUnit(id: 'a1', isObsolete: false);
        final obsolete1 = createTestUnit(id: 'o1', isObsolete: true);
        final obsolete2 = createTestUnit(id: 'o2', isObsolete: true);

        await repository.insert(active);
        await repository.insert(obsolete1);
        await repository.insert(obsolete2);

        final result = await repository.getObsolete('project-id');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((u) => u.isObsolete), isTrue);
      });
    });

    group('getByIds', () {
      test('should return units for given IDs', () async {
        final unit1 = createTestUnit(id: 'u1', key: 'key.1');
        final unit2 = createTestUnit(id: 'u2', key: 'key.2');
        final unit3 = createTestUnit(id: 'u3', key: 'key.3');

        await repository.insert(unit1);
        await repository.insert(unit2);
        await repository.insert(unit3);

        final result = await repository.getByIds(['u1', 'u3']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        final ids = result.value.map((u) => u.id).toSet();
        expect(ids, containsAll(['u1', 'u3']));
      });

      test('should return empty list for empty IDs', () async {
        final result = await repository.getByIds([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only found units', () async {
        final unit = createTestUnit(id: 'u1');
        await repository.insert(unit);

        final result = await repository.getByIds(['u1', 'non-existent']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
      });

      test('should handle large ID lists (batch processing)', () async {
        // Insert 20 units
        for (var i = 0; i < 20; i++) {
          final unit = createTestUnit(
            id: 'unit-$i',
            key: 'key.$i',
          );
          await repository.insert(unit);
        }

        final ids = List.generate(20, (i) => 'unit-$i');
        final result = await repository.getByIds(ids);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(20));
      });
    });

    group('markObsoleteByKeys', () {
      test('should mark multiple units as obsolete by keys', () async {
        final unit1 = createTestUnit(id: 'u1', key: 'key.1', isObsolete: false);
        final unit2 = createTestUnit(id: 'u2', key: 'key.2', isObsolete: false);
        final unit3 = createTestUnit(id: 'u3', key: 'key.3', isObsolete: false);

        await repository.insert(unit1);
        await repository.insert(unit2);
        await repository.insert(unit3);

        final result = await repository.markObsoleteByKeys(
          projectId: 'project-id',
          keys: ['key.1', 'key.3'],
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));

        // Verify units are obsolete
        final obsoleteResult = await repository.getObsolete('project-id');
        expect(obsoleteResult.value.length, equals(2));
      });

      test('should return 0 for empty keys list', () async {
        final result = await repository.markObsoleteByKeys(
          projectId: 'project-id',
          keys: [],
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should not mark already obsolete units', () async {
        final unit = createTestUnit(id: 'u1', key: 'key.1', isObsolete: true);
        await repository.insert(unit);

        final result = await repository.markObsoleteByKeys(
          projectId: 'project-id',
          keys: ['key.1'],
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should call progress callback', () async {
        final unit1 = createTestUnit(id: 'u1', key: 'key.1');
        final unit2 = createTestUnit(id: 'u2', key: 'key.2');
        await repository.insert(unit1);
        await repository.insert(unit2);

        final progressCalls = <int>[];
        await repository.markObsoleteByKeys(
          projectId: 'project-id',
          keys: ['key.1', 'key.2'],
          onProgress: (processed, total) {
            progressCalls.add(processed);
          },
        );

        expect(progressCalls, isNotEmpty);
      });
    });

    group('reactivateByKeys', () {
      test('should reactivate obsolete units and update source text', () async {
        final unit1 = createTestUnit(
          id: 'u1',
          key: 'key.1',
          sourceText: 'Old Text 1',
          isObsolete: true,
        );
        final unit2 = createTestUnit(
          id: 'u2',
          key: 'key.2',
          sourceText: 'Old Text 2',
          isObsolete: true,
        );

        await repository.insert(unit1);
        await repository.insert(unit2);

        final result = await repository.reactivateByKeys(
          projectId: 'project-id',
          sourceTextUpdates: {
            'key.1': 'New Text 1',
            'key.2': 'New Text 2',
          },
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));

        // Verify units are reactivated with new text
        final u1Result = await repository.getByKey('project-id', 'key.1');
        expect(u1Result.value.isObsolete, isFalse);
        expect(u1Result.value.sourceText, equals('New Text 1'));
      });

      test('should return 0 for empty updates', () async {
        final result = await repository.reactivateByKeys(
          projectId: 'project-id',
          sourceTextUpdates: {},
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should not reactivate non-obsolete units', () async {
        final unit = createTestUnit(
          id: 'u1',
          key: 'key.1',
          sourceText: 'Original',
          isObsolete: false,
        );
        await repository.insert(unit);

        final result = await repository.reactivateByKeys(
          projectId: 'project-id',
          sourceTextUpdates: {'key.1': 'New Text'},
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('updateSourceTexts', () {
      test('should update source texts for multiple units', () async {
        final unit1 = createTestUnit(id: 'u1', key: 'key.1', sourceText: 'Old 1');
        final unit2 = createTestUnit(id: 'u2', key: 'key.2', sourceText: 'Old 2');

        await repository.insert(unit1);
        await repository.insert(unit2);

        final result = await repository.updateSourceTexts(
          projectId: 'project-id',
          sourceTextUpdates: {
            'key.1': 'New 1',
            'key.2': 'New 2',
          },
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));

        // Verify updates
        final u1Result = await repository.getByKey('project-id', 'key.1');
        expect(u1Result.value.sourceText, equals('New 1'));
      });

      test('should return 0 for empty updates', () async {
        final result = await repository.updateSourceTexts(
          projectId: 'project-id',
          sourceTextUpdates: {},
        );

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('getTranslationRowsJoined', () {
      test('should return joined unit and version data', () async {
        // Insert unit
        final unit = createTestUnit(id: 'u1', key: 'test.key');
        await repository.insert(unit);

        // Insert version
        await db.insert('translation_versions', {
          'id': 'v1',
          'unit_id': 'u1',
          'project_language_id': 'pl1',
          'translated_text': 'Translated',
          'is_manually_edited': 0,
          'status': 'completed',
          'translation_source': 'ai',
          'validation_issues': null,
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });

        final result = await repository.getTranslationRowsJoined(
          projectId: 'project-id',
          projectLanguageId: 'pl1',
        );

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first['key'], equals('test.key'));
        expect(result.value.first['translated_text'], equals('Translated'));
      });

      test('should not return obsolete units', () async {
        final activeUnit = createTestUnit(id: 'active', key: 'active.key', isObsolete: false);
        final obsoleteUnit = createTestUnit(id: 'obsolete', key: 'obsolete.key', isObsolete: true);

        await repository.insert(activeUnit);
        await repository.insert(obsoleteUnit);

        // Insert versions for both
        await db.insert('translation_versions', {
          'id': 'v1',
          'unit_id': 'active',
          'project_language_id': 'pl1',
          'translated_text': 'Active Translation',
          'is_manually_edited': 0,
          'status': 'completed',
          'translation_source': 'ai',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });
        await db.insert('translation_versions', {
          'id': 'v2',
          'unit_id': 'obsolete',
          'project_language_id': 'pl1',
          'translated_text': 'Obsolete Translation',
          'is_manually_edited': 0,
          'status': 'completed',
          'translation_source': 'ai',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });

        final result = await repository.getTranslationRowsJoined(
          projectId: 'project-id',
          projectLanguageId: 'pl1',
        );

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first['key'], equals('active.key'));
      });

      test('should filter by project language', () async {
        final unit = createTestUnit(id: 'u1', key: 'test.key');
        await repository.insert(unit);

        // Insert versions for different languages
        await db.insert('translation_versions', {
          'id': 'v1',
          'unit_id': 'u1',
          'project_language_id': 'french',
          'translated_text': 'Bonjour',
          'is_manually_edited': 0,
          'status': 'completed',
          'translation_source': 'ai',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });
        await db.insert('translation_versions', {
          'id': 'v2',
          'unit_id': 'u1',
          'project_language_id': 'german',
          'translated_text': 'Hallo',
          'is_manually_edited': 0,
          'status': 'completed',
          'translation_source': 'ai',
          'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        });

        final result = await repository.getTranslationRowsJoined(
          projectId: 'project-id',
          projectLanguageId: 'french',
        );

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first['translated_text'], equals('Bonjour'));
      });
    });

    group('edge cases', () {
      test('should handle special characters in source text', () async {
        final unit = createTestUnit(
          sourceText: "Hello, it's a \"test\" with <special> & characters!",
        );

        final result = await repository.insert(unit);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(unit.id);
        expect(getResult.value.sourceText, contains('special'));
      });

      test('should handle unicode characters', () async {
        final unit = createTestUnit(
          sourceText: '\u4f60\u597d\u4e16\u754c', // Chinese: Hello World
        );

        final result = await repository.insert(unit);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(unit.id);
        expect(getResult.value.sourceText, equals('\u4f60\u597d\u4e16\u754c'));
      });

      test('should handle very long source text', () async {
        final longText = 'a' * 10000;
        final unit = createTestUnit(sourceText: longText);

        final result = await repository.insert(unit);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(unit.id);
        expect(getResult.value.sourceText.length, equals(10000));
      });

      test('should handle nullable context and notes', () async {
        final unit = TranslationUnit(
          id: 'null-fields',
          projectId: 'project-id',
          key: 'test.key',
          sourceText: 'Test',
          context: null,
          notes: null,
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(unit);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(unit.id);
        expect(getResult.value.context, isNull);
        expect(getResult.value.notes, isNull);
      });

      test('should handle source loc file path', () async {
        final unit = createTestUnit(
          sourceLocFile: 'text/db/unit_names__.loc',
        );

        final result = await repository.insert(unit);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById(unit.id);
        expect(getResult.value.sourceLocFile, equals('text/db/unit_names__.loc'));
      });
    });
  });
}
