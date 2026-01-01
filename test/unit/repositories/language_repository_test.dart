import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/services/database/database_service.dart';

void main() {
  late Database db;
  late LanguageRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Create languages table
    await db.execute('''
      CREATE TABLE languages (
        id TEXT PRIMARY KEY,
        code TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        native_name TEXT NOT NULL,
        is_active INTEGER DEFAULT 1,
        is_custom INTEGER DEFAULT 0
      )
    ''');

    // Initialize DatabaseService with the test database
    DatabaseService.setTestDatabase(db);

    repository = LanguageRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('LanguageRepository', () {
    Language createTestLanguage({
      String? id,
      String? code,
      String? name,
      String? nativeName,
      bool? isActive,
      bool? isCustom,
    }) {
      return Language(
        id: id ?? 'lang-id',
        code: code ?? 'en',
        name: name ?? 'English',
        nativeName: nativeName ?? 'English',
        isActive: isActive ?? true,
        isCustom: isCustom ?? false,
      );
    }

    group('insert', () {
      test('should insert a language successfully', () async {
        final language = createTestLanguage();

        final result = await repository.insert(language);

        expect(result.isOk, isTrue);
        expect(result.value, equals(language));

        // Verify it's in the database
        final maps = await db.query('languages', where: 'id = ?', whereArgs: [language.id]);
        expect(maps.length, equals(1));
        expect(maps.first['name'], equals('English'));
      });

      test('should fail when inserting duplicate ID', () async {
        final language = createTestLanguage();
        await repository.insert(language);

        final duplicate = createTestLanguage(name: 'Duplicate');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate code', () async {
        final language1 = createTestLanguage(id: 'lang-1', code: 'en');
        await repository.insert(language1);

        final language2 = createTestLanguage(id: 'lang-2', code: 'en');
        final result = await repository.insert(language2);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return language when found', () async {
        final language = createTestLanguage();
        await repository.insert(language);

        final result = await repository.getById(language.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(language.id));
        expect(result.value.code, equals(language.code));
        expect(result.value.name, equals(language.name));
      });

      test('should return error when language not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no languages exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all languages ordered by name ASC', () async {
        final german = createTestLanguage(id: 'de', code: 'de', name: 'German', nativeName: 'Deutsch');
        final english = createTestLanguage(id: 'en', code: 'en', name: 'English', nativeName: 'English');
        final french = createTestLanguage(id: 'fr', code: 'fr', name: 'French', nativeName: 'Francais');

        await repository.insert(german);
        await repository.insert(french);
        await repository.insert(english);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        // Should be ordered by name ASC
        expect(result.value[0].name, equals('English'));
        expect(result.value[1].name, equals('French'));
        expect(result.value[2].name, equals('German'));
      });
    });

    group('update', () {
      test('should update language successfully', () async {
        final language = createTestLanguage();
        await repository.insert(language);

        final updatedLanguage = language.copyWith(name: 'Updated English');
        final result = await repository.update(updatedLanguage);

        expect(result.isOk, isTrue);
        expect(result.value.name, equals('Updated English'));

        // Verify in database
        final getResult = await repository.getById(language.id);
        expect(getResult.value.name, equals('Updated English'));
      });

      test('should return error when language not found', () async {
        final language = createTestLanguage(id: 'non-existent');

        final result = await repository.update(language);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete language successfully', () async {
        final language = createTestLanguage();
        await repository.insert(language);

        final result = await repository.delete(language.id);

        expect(result.isOk, isTrue);

        // Verify it's deleted
        final getResult = await repository.getById(language.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when language not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByCode', () {
      test('should return language when code found', () async {
        final language = createTestLanguage(code: 'fr');
        await repository.insert(language);

        final result = await repository.getByCode('fr');

        expect(result.isOk, isTrue);
        expect(result.value.code, equals('fr'));
      });

      test('should return error when code not found', () async {
        final result = await repository.getByCode('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getActive', () {
      test('should return only active languages', () async {
        final activeLanguage = createTestLanguage(id: 'en', code: 'en', isActive: true);
        final inactiveLanguage = createTestLanguage(id: 'de', code: 'de', isActive: false);

        await repository.insert(activeLanguage);
        await repository.insert(inactiveLanguage);

        final result = await repository.getActive();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.code, equals('en'));
      });

      test('should return empty list when no active languages', () async {
        final inactiveLanguage = createTestLanguage(isActive: false);
        await repository.insert(inactiveLanguage);

        final result = await repository.getActive();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getByIds', () {
      test('should return languages for given IDs', () async {
        final lang1 = createTestLanguage(id: 'en', code: 'en', name: 'English');
        final lang2 = createTestLanguage(id: 'fr', code: 'fr', name: 'French');
        final lang3 = createTestLanguage(id: 'de', code: 'de', name: 'German');

        await repository.insert(lang1);
        await repository.insert(lang2);
        await repository.insert(lang3);

        final result = await repository.getByIds(['en', 'de']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        final codes = result.value.map((l) => l.code).toSet();
        expect(codes, containsAll(['en', 'de']));
      });

      test('should return empty list for empty IDs', () async {
        final result = await repository.getByIds([]);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only found languages', () async {
        final lang1 = createTestLanguage(id: 'en', code: 'en');
        await repository.insert(lang1);

        final result = await repository.getByIds(['en', 'non-existent']);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.id, equals('en'));
      });

      test('should handle large ID lists (batch processing)', () async {
        // Insert 10 languages
        for (var i = 0; i < 10; i++) {
          final lang = createTestLanguage(
            id: 'lang-$i',
            code: 'code-$i',
            name: 'Language $i',
          );
          await repository.insert(lang);
        }

        final ids = List.generate(10, (i) => 'lang-$i');
        final result = await repository.getByIds(ids);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(10));
      });
    });

    group('codeExists', () {
      test('should return true when code exists', () async {
        final language = createTestLanguage(code: 'en');
        await repository.insert(language);

        final result = await repository.codeExists('en');

        expect(result.isOk, isTrue);
        expect(result.value, isTrue);
      });

      test('should return false when code does not exist', () async {
        final result = await repository.codeExists('non-existent');

        expect(result.isOk, isTrue);
        expect(result.value, isFalse);
      });
    });

    group('getCustomLanguages', () {
      test('should return only custom languages', () async {
        final defaultLanguage = createTestLanguage(id: 'en', code: 'en', isCustom: false);
        final customLanguage = createTestLanguage(id: 'custom', code: 'xx', isCustom: true);

        await repository.insert(defaultLanguage);
        await repository.insert(customLanguage);

        final result = await repository.getCustomLanguages();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.isCustom, isTrue);
        expect(result.value.first.code, equals('xx'));
      });

      test('should return empty list when no custom languages', () async {
        final defaultLanguage = createTestLanguage(isCustom: false);
        await repository.insert(defaultLanguage);

        final result = await repository.getCustomLanguages();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('edge cases', () {
      test('should handle special characters in language names', () async {
        final language = createTestLanguage(
          id: 'zh',
          code: 'zh',
          name: 'Chinese',
          nativeName: '\u4e2d\u6587', // Chinese characters
        );

        final insertResult = await repository.insert(language);
        expect(insertResult.isOk, isTrue);

        final getResult = await repository.getById('zh');
        expect(getResult.isOk, isTrue);
        expect(getResult.value.nativeName, equals('\u4e2d\u6587'));
      });

      test('should handle updating active status', () async {
        final language = createTestLanguage(isActive: true);
        await repository.insert(language);

        final deactivated = language.copyWith(isActive: false);
        await repository.update(deactivated);

        final result = await repository.getById(language.id);
        expect(result.value.isActive, isFalse);
      });
    });
  });
}
