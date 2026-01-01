import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/setting.dart';
import 'package:twmt/repositories/settings_repository.dart';
import 'package:twmt/services/database/database_service.dart';

void main() {
  late Database db;
  late SettingsRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Create settings table
    await db.execute('''
      CREATE TABLE settings (
        id TEXT PRIMARY KEY,
        key TEXT NOT NULL UNIQUE,
        value TEXT NOT NULL,
        value_type TEXT NOT NULL DEFAULT 'string',
        updated_at INTEGER NOT NULL
      )
    ''');

    // Initialize DatabaseService with the test database
    DatabaseService.setTestDatabase(db);

    repository = SettingsRepository();
  });

  tearDown(() async {
    await db.close();
    DatabaseService.resetTestDatabase();
  });

  group('SettingsRepository', () {
    Setting createTestSetting({
      String? id,
      String? key,
      String? value,
      SettingValueType? valueType,
      int? updatedAt,
    }) {
      return Setting(
        id: id ?? 'setting-id',
        key: key ?? 'test.setting',
        value: value ?? 'test-value',
        valueType: valueType ?? SettingValueType.string,
        updatedAt: updatedAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
    }

    group('insert', () {
      test('should insert a setting successfully', () async {
        final setting = createTestSetting();

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);
        expect(result.value, equals(setting));

        // Verify it's in the database
        final maps = await db.query('settings', where: 'id = ?', whereArgs: [setting.id]);
        expect(maps.length, equals(1));
        expect(maps.first['key'], equals('test.setting'));
      });

      test('should fail when inserting duplicate ID', () async {
        final setting = createTestSetting();
        await repository.insert(setting);

        final duplicate = createTestSetting(key: 'different.key');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate key', () async {
        final setting1 = createTestSetting(id: 's1', key: 'same.key');
        await repository.insert(setting1);

        final setting2 = createTestSetting(id: 's2', key: 'same.key');
        final result = await repository.insert(setting2);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return setting when found', () async {
        final setting = createTestSetting();
        await repository.insert(setting);

        final result = await repository.getById(setting.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(setting.id));
        expect(result.value.key, equals(setting.key));
      });

      test('should return error when setting not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no settings exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all settings ordered by key ASC', () async {
        final setting1 = createTestSetting(id: 's1', key: 'z.setting');
        final setting2 = createTestSetting(id: 's2', key: 'a.setting');
        final setting3 = createTestSetting(id: 's3', key: 'm.setting');

        await repository.insert(setting1);
        await repository.insert(setting2);
        await repository.insert(setting3);

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].key, equals('a.setting'));
        expect(result.value[1].key, equals('m.setting'));
        expect(result.value[2].key, equals('z.setting'));
      });
    });

    group('update', () {
      test('should update setting successfully', () async {
        final setting = createTestSetting();
        await repository.insert(setting);

        final updated = setting.copyWith(value: 'updated-value');
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.value, equals('updated-value'));

        // Verify in database
        final getResult = await repository.getById(setting.id);
        expect(getResult.value.value, equals('updated-value'));
      });

      test('should return error when setting not found', () async {
        final setting = createTestSetting(id: 'non-existent');

        final result = await repository.update(setting);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete setting successfully', () async {
        final setting = createTestSetting();
        await repository.insert(setting);

        final result = await repository.delete(setting.id);

        expect(result.isOk, isTrue);

        // Verify it's deleted
        final getResult = await repository.getById(setting.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when setting not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByKey', () {
      test('should return setting when key found', () async {
        final setting = createTestSetting(key: 'app.theme');
        await repository.insert(setting);

        final result = await repository.getByKey('app.theme');

        expect(result.isOk, isTrue);
        expect(result.value.key, equals('app.theme'));
      });

      test('should return error when key not found', () async {
        final result = await repository.getByKey('non.existent.key');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getValue', () {
      test('should return value for existing key', () async {
        final setting = createTestSetting(key: 'app.language', value: 'en');
        await repository.insert(setting);

        final result = await repository.getValue('app.language');

        expect(result.isOk, isTrue);
        expect(result.value, equals('en'));
      });

      test('should return error when key not found', () async {
        final result = await repository.getValue('non.existent');

        expect(result.isErr, isTrue);
      });
    });

    group('setValue', () {
      test('should create new setting when key does not exist', () async {
        final result = await repository.setValue(
          'new.setting',
          'new-value',
          SettingValueType.string,
        );

        expect(result.isOk, isTrue);
        expect(result.value.key, equals('new.setting'));
        expect(result.value.value, equals('new-value'));

        // Verify in database
        final getResult = await repository.getByKey('new.setting');
        expect(getResult.isOk, isTrue);
      });

      test('should update existing setting when key exists', () async {
        final setting = createTestSetting(key: 'existing.setting', value: 'old-value');
        await repository.insert(setting);

        final result = await repository.setValue(
          'existing.setting',
          'new-value',
          SettingValueType.string,
        );

        expect(result.isOk, isTrue);
        expect(result.value.value, equals('new-value'));

        // Verify the ID is the same (updated, not created new)
        final getResult = await repository.getByKey('existing.setting');
        expect(getResult.value.id, equals(setting.id));
      });

      test('should update value type when changing', () async {
        final setting = createTestSetting(
          key: 'type.setting',
          value: 'text',
          valueType: SettingValueType.string,
        );
        await repository.insert(setting);

        final result = await repository.setValue(
          'type.setting',
          '42',
          SettingValueType.integer,
        );

        expect(result.isOk, isTrue);
        expect(result.value.valueType, equals(SettingValueType.integer));
      });
    });

    group('value types', () {
      test('should handle string value type', () async {
        final setting = Setting.string(
          id: 's1',
          key: 'string.setting',
          value: 'hello world',
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);
        expect(result.value.valueType, equals(SettingValueType.string));
        expect(result.value.stringValue, equals('hello world'));
      });

      test('should handle integer value type', () async {
        final setting = Setting.integer(
          id: 's2',
          key: 'integer.setting',
          value: 42,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);
        expect(result.value.valueType, equals(SettingValueType.integer));
        expect(result.value.intValue, equals(42));
      });

      test('should handle boolean value type', () async {
        final setting = Setting.boolean(
          id: 's3',
          key: 'boolean.setting',
          value: true,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);
        expect(result.value.valueType, equals(SettingValueType.boolean));
        expect(result.value.boolValue, isTrue);
      });

      test('should handle json value type', () async {
        final setting = Setting.json(
          id: 's4',
          key: 'json.setting',
          value: '{"theme": "dark", "fontSize": 14}',
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);
        expect(result.value.valueType, equals(SettingValueType.json));
        expect(result.value.stringValue, contains('theme'));
      });
    });

    group('edge cases', () {
      test('should handle empty string value', () async {
        final setting = createTestSetting(value: '');

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);
        expect(result.value.value, equals(''));
      });

      test('should handle special characters in value', () async {
        final setting = createTestSetting(
          value: "Special chars: !@#\$%^&*()_+-=[]{}|;':\",./<>?",
        );

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(setting.id);
        expect(getResult.value.value, contains('Special chars'));
      });

      test('should handle unicode in value', () async {
        final setting = createTestSetting(
          value: '\u4e2d\u6587\u65e5\u672c\u8a9e\ud55c\uad6d\uc5b4', // Chinese, Japanese, Korean
        );

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(setting.id);
        expect(getResult.value.value, equals('\u4e2d\u6587\u65e5\u672c\u8a9e\ud55c\uad6d\uc5b4'));
      });

      test('should handle long value', () async {
        final longValue = 'a' * 10000;
        final setting = createTestSetting(value: longValue);

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(setting.id);
        expect(getResult.value.value.length, equals(10000));
      });

      test('should handle keys with dots', () async {
        final setting = createTestSetting(key: 'app.settings.theme.color.primary');

        final result = await repository.insert(setting);

        expect(result.isOk, isTrue);

        final getResult = await repository.getByKey('app.settings.theme.color.primary');
        expect(getResult.isOk, isTrue);
      });

      test('should update timestamp on setValue', () async {
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final setting = createTestSetting(key: 'timestamp.test', updatedAt: now - 1000);
        await repository.insert(setting);

        await Future.delayed(const Duration(milliseconds: 100));

        final result = await repository.setValue(
          'timestamp.test',
          'new-value',
          SettingValueType.string,
        );

        expect(result.isOk, isTrue);
        expect(result.value.updatedAt, greaterThanOrEqualTo(now));
      });
    });

    group('concurrent access', () {
      test('should handle multiple setValue calls for same key', () async {
        // Insert initial setting
        await repository.setValue('concurrent.key', 'value1', SettingValueType.string);

        // Multiple updates
        await repository.setValue('concurrent.key', 'value2', SettingValueType.string);
        await repository.setValue('concurrent.key', 'value3', SettingValueType.string);

        final result = await repository.getValue('concurrent.key');
        expect(result.value, equals('value3'));
      });
    });
  });
}
