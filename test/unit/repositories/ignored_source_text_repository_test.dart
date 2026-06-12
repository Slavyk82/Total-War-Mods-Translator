import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/repositories/ignored_source_text_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late IgnoredSourceTextRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = IgnoredSourceTextRepository();
    // The IgnoredSourceTextsMigration seeds 4 default rows and
    // TestDatabase.openMigrated does NOT clear this table. Clear it here so
    // each test starts from a known-empty state and assertions on counts /
    // getAll are deterministic. This is a test-side cleanup only.
    await db.delete('ignored_source_texts');
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('IgnoredSourceTextRepository', () {
    // The table has NO `created_at <= updated_at` CHECK constraint, but we
    // keep created_at small/old to be safe and to mirror conventions.
    IgnoredSourceText createTestText({
      String? id,
      String? sourceText,
      bool isEnabled = true,
      int? createdAt,
      int? updatedAt,
    }) {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return IgnoredSourceText(
        id: id ?? 'ist-id',
        sourceText: sourceText ?? 'placeholder',
        isEnabled: isEnabled,
        createdAt: createdAt ?? 1000,
        updatedAt: updatedAt ?? now,
      );
    }

    group('insert', () {
      test('should insert an ignored source text successfully', () async {
        final entity = createTestText();

        final result = await repository.insert(entity);

        expect(result.isOk, isTrue);
        expect(result.value, equals(entity));

        final maps =
            await db.query('ignored_source_texts', where: 'id = ?', whereArgs: [entity.id]);
        expect(maps.length, equals(1));
        expect(maps.first['source_text'], equals('placeholder'));
        expect(maps.first['is_enabled'], equals(1));
      });

      test('should fail when inserting duplicate ID', () async {
        await repository.insert(createTestText(id: 'dup', sourceText: 'one'));

        final result =
            await repository.insert(createTestText(id: 'dup', sourceText: 'two'));

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate text (case-insensitive)', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'Dummy'));

        final result =
            await repository.insert(createTestText(id: 's2', sourceText: 'dummy'));

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return entity when found', () async {
        final entity = createTestText();
        await repository.insert(entity);

        final result = await repository.getById(entity.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(entity.id));
        expect(result.value.sourceText, equals(entity.sourceText));
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

      test('should return all entries ordered by source_text ASC', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'zeta'));
        await repository.insert(createTestText(id: 's2', sourceText: 'alpha'));
        await repository.insert(createTestText(id: 's3', sourceText: 'mike'));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].sourceText, equals('alpha'));
        expect(result.value[1].sourceText, equals('mike'));
        expect(result.value[2].sourceText, equals('zeta'));
      });
    });

    group('update', () {
      test('should update entity successfully', () async {
        final entity = createTestText();
        await repository.insert(entity);

        final updated = entity.copyWith(sourceText: 'updated-text', isEnabled: false);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.sourceText, equals('updated-text'));

        final getResult = await repository.getById(entity.id);
        expect(getResult.value.sourceText, equals('updated-text'));
        expect(getResult.value.isEnabled, isFalse);
      });

      test('should return error when entity not found', () async {
        final result = await repository.update(createTestText(id: 'non-existent'));

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete entity successfully', () async {
        final entity = createTestText();
        await repository.insert(entity);

        final result = await repository.delete(entity.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(entity.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when entity not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getEnabledTexts', () {
      test('should return only enabled texts ordered by source_text ASC', () async {
        await repository.insert(
            createTestText(id: 's1', sourceText: 'zeta', isEnabled: true));
        await repository.insert(
            createTestText(id: 's2', sourceText: 'alpha', isEnabled: true));
        await repository.insert(
            createTestText(id: 's3', sourceText: 'disabled', isEnabled: false));

        final result = await repository.getEnabledTexts();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].sourceText, equals('alpha'));
        expect(result.value[1].sourceText, equals('zeta'));
        expect(result.value.every((e) => e.isEnabled), isTrue);
      });

      test('should return empty list when no enabled texts exist', () async {
        await repository.insert(
            createTestText(id: 's1', sourceText: 'off', isEnabled: false));

        final result = await repository.getEnabledTexts();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('toggleEnabled', () {
      test('should toggle enabled -> disabled and bump updated_at', () async {
        final entity = createTestText(
          id: 's1',
          sourceText: 'toggle-me',
          isEnabled: true,
          createdAt: 1000,
          updatedAt: 1000,
        );
        await repository.insert(entity);

        final result = await repository.toggleEnabled(entity.id);

        expect(result.isOk, isTrue);
        expect(result.value.isEnabled, isFalse);
        expect(result.value.updatedAt, greaterThan(1000));

        final getResult = await repository.getById(entity.id);
        expect(getResult.value.isEnabled, isFalse);
      });

      test('should toggle disabled -> enabled', () async {
        final entity = createTestText(
          id: 's2',
          sourceText: 'toggle-back',
          isEnabled: false,
        );
        await repository.insert(entity);

        final result = await repository.toggleEnabled(entity.id);

        expect(result.isOk, isTrue);
        expect(result.value.isEnabled, isTrue);
      });

      test('should return error when not found', () async {
        final result = await repository.toggleEnabled('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('existsByText', () {
      test('should return true when text exists (case-insensitive, trimmed)', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'Placeholder'));

        final result = await repository.existsByText('  placeholder  ');

        expect(result.isOk, isTrue);
        expect(result.value, isTrue);
      });

      test('should return false when text does not exist', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'placeholder'));

        final result = await repository.existsByText('nonexistent');

        expect(result.isOk, isTrue);
        expect(result.value, isFalse);
      });
    });

    group('existsByTextExcludingId', () {
      test('should return true when another row has the text', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'shared'));
        await repository.insert(createTestText(id: 's2', sourceText: 'other'));

        final result = await repository.existsByTextExcludingId('SHARED', 's2');

        expect(result.isOk, isTrue);
        expect(result.value, isTrue);
      });

      test('should return false when only the excluded row has the text', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'unique'));

        final result = await repository.existsByTextExcludingId('unique', 's1');

        expect(result.isOk, isTrue);
        expect(result.value, isFalse);
      });
    });

    group('getTotalCount', () {
      test('should return total count of all rows', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'a'));
        await repository.insert(
            createTestText(id: 's2', sourceText: 'b', isEnabled: false));

        final result = await repository.getTotalCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('should return 0 when empty', () async {
        final result = await repository.getTotalCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('getEnabledCount', () {
      test('should count only enabled rows', () async {
        await repository.insert(
            createTestText(id: 's1', sourceText: 'a', isEnabled: true));
        await repository.insert(
            createTestText(id: 's2', sourceText: 'b', isEnabled: true));
        await repository.insert(
            createTestText(id: 's3', sourceText: 'c', isEnabled: false));

        final result = await repository.getEnabledCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));
      });

      test('should return 0 when empty', () async {
        final result = await repository.getEnabledCount();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('deleteAll', () {
      test('should delete all rows and return the deleted count', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'a'));
        await repository.insert(createTestText(id: 's2', sourceText: 'b'));
        await repository.insert(createTestText(id: 's3', sourceText: 'c'));

        final result = await repository.deleteAll();

        expect(result.isOk, isTrue);
        expect(result.value, equals(3));

        final countResult = await repository.getTotalCount();
        expect(countResult.value, equals(0));
      });

      test('should return 0 when already empty', () async {
        final result = await repository.deleteAll();

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('insertDefaults', () {
      test('should insert the default texts', () async {
        final result = await repository.insertDefaults();

        expect(result.isOk, isTrue);
        expect(
          result.value.length,
          equals(IgnoredSourceTextRepository.defaultTexts.length),
        );

        final texts = result.value.map((e) => e.sourceText).toList();
        expect(texts, containsAll(IgnoredSourceTextRepository.defaultTexts));
        expect(result.value.every((e) => e.isEnabled), isTrue);

        final countResult = await repository.getTotalCount();
        expect(
          countResult.value,
          equals(IgnoredSourceTextRepository.defaultTexts.length),
        );
      });

      test('should fail when a default text already exists (unique constraint)',
          () async {
        // Pre-insert one of the default texts so insertDefaults hits the
        // case-insensitive unique index and aborts.
        await repository.insert(createTestText(
          id: 'pre',
          sourceText: IgnoredSourceTextRepository.defaultTexts.first,
        ));

        final result = await repository.insertDefaults();

        expect(result.isErr, isTrue);
      });
    });

    group('resetToDefaults', () {
      test('should wipe existing rows and insert defaults (transaction)', () async {
        await repository.insert(createTestText(id: 's1', sourceText: 'custom-one'));
        await repository.insert(createTestText(id: 's2', sourceText: 'custom-two'));

        final result = await repository.resetToDefaults();

        expect(result.isOk, isTrue);
        expect(
          result.value.length,
          equals(IgnoredSourceTextRepository.defaultTexts.length),
        );

        final all = await repository.getAll();
        final texts = all.value.map((e) => e.sourceText).toList();
        expect(
          all.value.length,
          equals(IgnoredSourceTextRepository.defaultTexts.length),
        );
        expect(texts, containsAll(IgnoredSourceTextRepository.defaultTexts));
        // Custom entries are gone.
        expect(texts, isNot(contains('custom-one')));
        expect(texts, isNot(contains('custom-two')));
      });

      test('should insert defaults when starting from empty', () async {
        final result = await repository.resetToDefaults();

        expect(result.isOk, isTrue);

        final countResult = await repository.getTotalCount();
        expect(
          countResult.value,
          equals(IgnoredSourceTextRepository.defaultTexts.length),
        );
      });
    });
  });
}
