import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/repositories/project_language_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late ProjectLanguageRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = ProjectLanguageRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('ProjectLanguageRepository', () {
    // Timestamps are stored in SECONDS. The project_languages CHECK constraint
    // requires created_at <= updated_at, and progress_percent in [0, 100].
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    ProjectLanguage createTestProjectLanguage({
      String? id,
      String? projectId,
      String? languageId,
      ProjectLanguageStatus? status,
      double? progressPercent,
      int? createdAt,
      int? updatedAt,
    }) {
      final created = createdAt ?? nowSeconds;
      return ProjectLanguage(
        id: id ?? 'pl-id',
        projectId: projectId ?? 'project-1',
        languageId: languageId ?? 'language-1',
        status: status ?? ProjectLanguageStatus.pending,
        progressPercent: progressPercent ?? 0.0,
        createdAt: created,
        // Keep updated_at >= created_at to satisfy the CHECK constraint.
        updatedAt: updatedAt ?? created,
      );
    }

    group('insert', () {
      test('should insert a project language successfully', () async {
        final pl = createTestProjectLanguage();

        final result = await repository.insert(pl);

        expect(result.isOk, isTrue);
        expect(result.value, equals(pl));

        final maps =
            await db.query('project_languages', where: 'id = ?', whereArgs: [pl.id]);
        expect(maps.length, equals(1));
        expect(maps.first['project_id'], equals('project-1'));
        expect(maps.first['language_id'], equals('language-1'));
        expect(maps.first['status'], equals('pending'));
      });

      test('should fail when inserting duplicate ID', () async {
        final pl = createTestProjectLanguage();
        await repository.insert(pl);

        final duplicate =
            createTestProjectLanguage(projectId: 'project-2', languageId: 'language-2');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when violating UNIQUE(project_id, language_id)', () async {
        final pl1 = createTestProjectLanguage(
          id: 'pl-1',
          projectId: 'project-x',
          languageId: 'language-x',
        );
        await repository.insert(pl1);

        final pl2 = createTestProjectLanguage(
          id: 'pl-2',
          projectId: 'project-x',
          languageId: 'language-x',
        );
        final result = await repository.insert(pl2);

        expect(result.isErr, isTrue);
      });

      test('should persist non-default status and progress', () async {
        final pl = createTestProjectLanguage(
          status: ProjectLanguageStatus.translating,
          progressPercent: 42.5,
        );

        final result = await repository.insert(pl);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(pl.id);
        expect(getResult.value.status, equals(ProjectLanguageStatus.translating));
        expect(getResult.value.progressPercent, equals(42.5));
      });
    });

    group('getById', () {
      test('should return project language when found', () async {
        final pl = createTestProjectLanguage();
        await repository.insert(pl);

        final result = await repository.getById(pl.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(pl.id));
        expect(result.value.projectId, equals(pl.projectId));
        expect(result.value.languageId, equals(pl.languageId));
      });

      test('should return error when not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when none exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all ordered by created_at DESC', () async {
        final older = createTestProjectLanguage(
          id: 'pl-old',
          languageId: 'lang-old',
          createdAt: nowSeconds - 100,
        );
        final newer = createTestProjectLanguage(
          id: 'pl-new',
          languageId: 'lang-new',
          createdAt: nowSeconds + 100,
        );
        final middle = createTestProjectLanguage(
          id: 'pl-mid',
          languageId: 'lang-mid',
          createdAt: nowSeconds,
        );

        await repository.insert(older);
        await repository.insert(newer);
        await repository.insert(middle);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        // DESC: newest first
        expect(result.value[0].id, equals('pl-new'));
        expect(result.value[1].id, equals('pl-mid'));
        expect(result.value[2].id, equals('pl-old'));
      });
    });

    group('update', () {
      test('should update a project language successfully', () async {
        final pl = createTestProjectLanguage();
        await repository.insert(pl);

        final updated = pl.copyWith(
          status: ProjectLanguageStatus.completed,
          progressPercent: 100.0,
          updatedAt: pl.createdAt + 10,
        );
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.status, equals(ProjectLanguageStatus.completed));

        final getResult = await repository.getById(pl.id);
        expect(getResult.value.status, equals(ProjectLanguageStatus.completed));
        expect(getResult.value.progressPercent, equals(100.0));
      });

      test('should return error when updating non-existent row', () async {
        final pl = createTestProjectLanguage(id: 'non-existent');

        final result = await repository.update(pl);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete a project language with no versions', () async {
        final pl = createTestProjectLanguage();
        await repository.insert(pl);

        final result = await repository.delete(pl.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(pl.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when deleting non-existent row', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByProject', () {
      test('should return only languages of the given project, ordered by created_at ASC',
          () async {
        final a = createTestProjectLanguage(
          id: 'pl-a',
          projectId: 'project-A',
          languageId: 'lang-a',
          createdAt: nowSeconds,
        );
        final b = createTestProjectLanguage(
          id: 'pl-b',
          projectId: 'project-A',
          languageId: 'lang-b',
          createdAt: nowSeconds + 50,
        );
        final other = createTestProjectLanguage(
          id: 'pl-other',
          projectId: 'project-B',
          languageId: 'lang-a',
          createdAt: nowSeconds,
        );

        await repository.insert(b);
        await repository.insert(a);
        await repository.insert(other);

        final result = await repository.getByProject('project-A');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        // ASC by created_at: 'pl-a' (earlier) before 'pl-b'
        expect(result.value[0].id, equals('pl-a'));
        expect(result.value[1].id, equals('pl-b'));
      });

      test('should return empty list when project has no languages', () async {
        final result = await repository.getByProject('unknown-project');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getByProjectAndLanguage', () {
      test('should return the matching project language', () async {
        final pl = createTestProjectLanguage(
          projectId: 'project-P',
          languageId: 'language-L',
        );
        await repository.insert(pl);

        final result =
            await repository.getByProjectAndLanguage('project-P', 'language-L');

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(pl.id));
      });

      test('should return an Err when no row matches', () async {
        // getByProjectAndLanguage throws (Err) on not-found, unlike
        // findByProjectAndLanguage which returns Ok(null).
        final result =
            await repository.getByProjectAndLanguage('nope', 'nope');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('findByProjectAndLanguage', () {
      test('should return Ok with the entity when found', () async {
        final pl = createTestProjectLanguage(
          projectId: 'project-F',
          languageId: 'language-F',
        );
        await repository.insert(pl);

        final result =
            await repository.findByProjectAndLanguage('project-F', 'language-F');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals(pl.id));
      });

      test('should return Ok(null) when no row matches', () async {
        final result =
            await repository.findByProjectAndLanguage('missing', 'missing');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('updateProgress', () {
      test('should update progress_percent and return the updated entity', () async {
        final pl = createTestProjectLanguage(progressPercent: 0.0);
        await repository.insert(pl);

        final result = await repository.updateProgress(pl.id, 75.0);

        expect(result.isOk, isTrue);
        expect(result.value.progressPercent, equals(75.0));

        // Verify persisted via raw query.
        final maps =
            await db.query('project_languages', where: 'id = ?', whereArgs: [pl.id]);
        expect(maps.first['progress_percent'], equals(75.0));
      });

      test('should accept boundary value 100 (CHECK <= 100)', () async {
        final pl = createTestProjectLanguage();
        await repository.insert(pl);

        final result = await repository.updateProgress(pl.id, 100.0);

        expect(result.isOk, isTrue);
        expect(result.value.progressPercent, equals(100.0));
      });

      test('should return error when row does not exist', () async {
        final result = await repository.updateProgress('non-existent-id', 50.0);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });

      test('should fail when progress violates CHECK (> 100)', () async {
        final pl = createTestProjectLanguage();
        await repository.insert(pl);

        // CHECK (progress_percent >= 0 AND progress_percent <= 100) is enforced
        // even with FK off, so the underlying UPDATE raises and is wrapped in Err.
        final result = await repository.updateProgress(pl.id, 150.0);

        expect(result.isErr, isTrue);
      });
    });

    group('countByLanguageId', () {
      test('should return 0 when no rows reference the language', () async {
        final result = await repository.countByLanguageId('unused-language');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should count rows referencing the given language', () async {
        await repository.insert(createTestProjectLanguage(
          id: 'pl-1',
          projectId: 'project-1',
          languageId: 'shared-lang',
        ));
        await repository.insert(createTestProjectLanguage(
          id: 'pl-2',
          projectId: 'project-2',
          languageId: 'shared-lang',
        ));
        await repository.insert(createTestProjectLanguage(
          id: 'pl-3',
          projectId: 'project-3',
          languageId: 'other-lang',
        ));

        final result = await repository.countByLanguageId('shared-lang');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });
    });
  });
}
