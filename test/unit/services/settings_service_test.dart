import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/setting.dart';
import 'package:twmt/repositories/settings_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';

// Mock class
class MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  late SettingsService service;
  late MockSettingsRepository mockRepository;

  setUpAll(() {
    // Register fallback values for mocktail
    registerFallbackValue(SettingValueType.string);
  });

  setUp(() {
    mockRepository = MockSettingsRepository();
    service = SettingsService(mockRepository);
  });

  group('SettingsService', () {
    // =========================================================================
    // getSetting
    // =========================================================================
    group('getSetting', () {
      test('should return setting when key exists', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'test_key',
          value: 'test_value',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('test_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getSetting('test_key');

        // Assert
        expect(result.isOk, true);
        expect(result.value, setting);
        verify(() => mockRepository.getByKey('test_key')).called(1);
      });

      test('should return error when key does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('nonexistent'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getSetting('nonexistent');

        // Assert
        expect(result.isErr, true);
      });
    });

    // =========================================================================
    // getString
    // =========================================================================
    group('getString', () {
      test('should return value when setting exists and is string type', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'string_key',
          value: 'hello world',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('string_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getString('string_key');

        // Assert
        expect(result, 'hello world');
      });

      test('should return default value when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('nonexistent'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getString('nonexistent', defaultValue: 'default');

        // Assert
        expect(result, 'default');
      });

      test('should return default value when setting has wrong type', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'int_key',
          value: '42',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('int_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getString('int_key', defaultValue: 'default');

        // Assert
        expect(result, 'default');
      });
    });

    // =========================================================================
    // getInt
    // =========================================================================
    group('getInt', () {
      test('should return parsed integer when setting exists and is integer type', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'int_key',
          value: '42',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('int_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getInt('int_key');

        // Assert
        expect(result, 42);
      });

      test('should return default value when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('nonexistent'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getInt('nonexistent', defaultValue: 100);

        // Assert
        expect(result, 100);
      });

      test('should return default value when integer parsing fails', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'invalid_int',
          value: 'not_a_number',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('invalid_int'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getInt('invalid_int', defaultValue: 99);

        // Assert
        expect(result, 99);
      });

      test('should return default value when setting has wrong type', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'string_key',
          value: '42',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('string_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getInt('string_key', defaultValue: 0);

        // Assert
        expect(result, 0);
      });
    });

    // =========================================================================
    // getBool
    // =========================================================================
    group('getBool', () {
      test('should return true when setting value is "true"', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'bool_key',
          value: 'true',
          valueType: SettingValueType.boolean,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('bool_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getBool('bool_key');

        // Assert
        expect(result, true);
      });

      test('should return false when setting value is "false"', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'bool_key',
          value: 'false',
          valueType: SettingValueType.boolean,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('bool_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getBool('bool_key');

        // Assert
        expect(result, false);
      });

      test('should handle case-insensitive "TRUE"', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'bool_key',
          value: 'TRUE',
          valueType: SettingValueType.boolean,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('bool_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getBool('bool_key');

        // Assert
        expect(result, true);
      });

      test('should return default value when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('nonexistent'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getBool('nonexistent', defaultValue: true);

        // Assert
        expect(result, true);
      });

      test('should return default value when setting has wrong type', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'string_key',
          value: 'true',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('string_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getBool('string_key', defaultValue: false);

        // Assert
        expect(result, false);
      });
    });

    // =========================================================================
    // getJson
    // =========================================================================
    group('getJson', () {
      test('should return JSON string when setting exists and is JSON type', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'json_key',
          value: '{"name": "test"}',
          valueType: SettingValueType.json,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('json_key'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getJson('json_key');

        // Assert
        expect(result, '{"name": "test"}');
      });

      test('should return default JSON when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('nonexistent'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getJson('nonexistent');

        // Assert
        expect(result, '{}');
      });
    });

    // =========================================================================
    // setString
    // =========================================================================
    group('setString', () {
      test('should delegate to repository with correct parameters', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'new_key',
          value: 'new_value',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue('new_key', 'new_value', SettingValueType.string))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setString('new_key', 'new_value');

        // Assert
        expect(result.isOk, true);
        verify(() => mockRepository.setValue('new_key', 'new_value', SettingValueType.string))
            .called(1);
      });
    });

    // =========================================================================
    // setInt
    // =========================================================================
    group('setInt', () {
      test('should convert integer to string and delegate to repository', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'int_key',
          value: '42',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue('int_key', '42', SettingValueType.integer))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setInt('int_key', 42);

        // Assert
        expect(result.isOk, true);
        verify(() => mockRepository.setValue('int_key', '42', SettingValueType.integer))
            .called(1);
      });
    });

    // =========================================================================
    // setBool
    // =========================================================================
    group('setBool', () {
      test('should convert boolean to string "true" and delegate to repository', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'bool_key',
          value: 'true',
          valueType: SettingValueType.boolean,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue('bool_key', 'true', SettingValueType.boolean))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setBool('bool_key', true);

        // Assert
        expect(result.isOk, true);
        verify(() => mockRepository.setValue('bool_key', 'true', SettingValueType.boolean))
            .called(1);
      });

      test('should convert boolean to string "false" and delegate to repository', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'bool_key',
          value: 'false',
          valueType: SettingValueType.boolean,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue('bool_key', 'false', SettingValueType.boolean))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setBool('bool_key', false);

        // Assert
        expect(result.isOk, true);
        verify(() => mockRepository.setValue('bool_key', 'false', SettingValueType.boolean))
            .called(1);
      });
    });

    // =========================================================================
    // setDefaultBatchSize
    // =========================================================================
    group('setDefaultBatchSize', () {
      test('should return error when batch size is less than 1', () async {
        // Act
        final result = await service.setDefaultBatchSize(0);

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, 'Batch size must be between 1 and 100');
        verifyNever(() => mockRepository.setValue(any(), any(), any()));
      });

      test('should return error when batch size is greater than 100', () async {
        // Act
        final result = await service.setDefaultBatchSize(101);

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, 'Batch size must be between 1 and 100');
      });

      test('should save valid batch size', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_batch_size',
          value: '50',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue(
              'default_batch_size',
              '50',
              SettingValueType.integer,
            )).thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setDefaultBatchSize(50);

        // Assert
        expect(result.isOk, true);
      });

      test('should accept minimum valid batch size (1)', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_batch_size',
          value: '1',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue(
              'default_batch_size',
              '1',
              SettingValueType.integer,
            )).thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setDefaultBatchSize(1);

        // Assert
        expect(result.isOk, true);
      });

      test('should accept maximum valid batch size (100)', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_batch_size',
          value: '100',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue(
              'default_batch_size',
              '100',
              SettingValueType.integer,
            )).thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setDefaultBatchSize(100);

        // Assert
        expect(result.isOk, true);
      });
    });

    // =========================================================================
    // setDefaultParallelBatches
    // =========================================================================
    group('setDefaultParallelBatches', () {
      test('should return error when count is less than 1', () async {
        // Act
        final result = await service.setDefaultParallelBatches(0);

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, 'Parallel batches must be between 1 and 20');
      });

      test('should return error when count is greater than 20', () async {
        // Act
        final result = await service.setDefaultParallelBatches(21);

        // Assert
        expect(result.isErr, true);
        expect(result.error.message, 'Parallel batches must be between 1 and 20');
      });

      test('should save valid parallel batches count', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_parallel_batches',
          value: '10',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.setValue(
              'default_parallel_batches',
              '10',
              SettingValueType.integer,
            )).thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.setDefaultParallelBatches(10);

        // Assert
        expect(result.isOk, true);
      });
    });

    // =========================================================================
    // getDefaultBatchSize
    // =========================================================================
    group('getDefaultBatchSize', () {
      test('should return stored batch size', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_batch_size',
          value: '30',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('default_batch_size'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getDefaultBatchSize();

        // Assert
        expect(result, 30);
      });

      test('should return 25 as default when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('default_batch_size'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getDefaultBatchSize();

        // Assert
        expect(result, 25);
      });
    });

    // =========================================================================
    // getDefaultParallelBatches
    // =========================================================================
    group('getDefaultParallelBatches', () {
      test('should return stored parallel batches count', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_parallel_batches',
          value: '8',
          valueType: SettingValueType.integer,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('default_parallel_batches'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getDefaultParallelBatches();

        // Assert
        expect(result, 8);
      });

      test('should return 5 as default when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('default_parallel_batches'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getDefaultParallelBatches();

        // Assert
        expect(result, 5);
      });
    });

    // =========================================================================
    // getRpfmPath / setRpfmPath
    // =========================================================================
    group('getRpfmPath', () {
      test('should return path when setting exists', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'rpfm_path',
          value: 'C:/RPFM/rpfm_cli.exe',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('rpfm_path'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getRpfmPath();

        // Assert
        expect(result, 'C:/RPFM/rpfm_cli.exe');
      });

      test('should return null when path is empty', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'rpfm_path',
          value: '',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('rpfm_path'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getRpfmPath();

        // Assert
        expect(result, null);
      });

      test('should return null when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('rpfm_path'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getRpfmPath();

        // Assert
        expect(result, null);
      });
    });

    // =========================================================================
    // getTotalWarGame
    // =========================================================================
    group('getTotalWarGame', () {
      test('should return stored game when setting exists', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'total_war_game',
          value: 'warhammer_2',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('total_war_game'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getTotalWarGame();

        // Assert
        expect(result, 'warhammer_2');
      });

      test('should return "warhammer_3" as default when setting is empty', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'total_war_game',
          value: '',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('total_war_game'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getTotalWarGame();

        // Assert
        expect(result, 'warhammer_3');
      });

      test('should return "warhammer_3" as default when setting does not exist', () async {
        // Arrange
        when(() => mockRepository.getByKey('total_war_game'))
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Setting not found'),
                ));

        // Act
        final result = await service.getTotalWarGame();

        // Assert
        expect(result, 'warhammer_3');
      });
    });

    // =========================================================================
    // getDefaultGameId
    // =========================================================================
    group('getDefaultGameId', () {
      test('should return game ID when setting exists', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_game_installation_id',
          value: 'game-123',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('default_game_installation_id'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getDefaultGameId();

        // Assert
        expect(result, 'game-123');
      });

      test('should return null when value is empty', () async {
        // Arrange
        const setting = Setting(
          id: 'setting-1',
          key: 'default_game_installation_id',
          value: '',
          valueType: SettingValueType.string,
          updatedAt: 1234567890,
        );
        when(() => mockRepository.getByKey('default_game_installation_id'))
            .thenAnswer((_) async => const Ok(setting));

        // Act
        final result = await service.getDefaultGameId();

        // Assert
        expect(result, null);
      });
    });

    // =========================================================================
    // getAllSettings
    // =========================================================================
    group('getAllSettings', () {
      test('should return all settings from repository', () async {
        // Arrange
        final settings = [
          const Setting(
            id: 'setting-1',
            key: 'key1',
            value: 'value1',
            valueType: SettingValueType.string,
            updatedAt: 1234567890,
          ),
          const Setting(
            id: 'setting-2',
            key: 'key2',
            value: '42',
            valueType: SettingValueType.integer,
            updatedAt: 1234567891,
          ),
        ];
        when(() => mockRepository.getAll())
            .thenAnswer((_) async => Ok(settings));

        // Act
        final result = await service.getAllSettings();

        // Assert
        expect(result.isOk, true);
        expect(result.value.length, 2);
        expect(result.value[0].key, 'key1');
        expect(result.value[1].key, 'key2');
      });

      test('should return error when repository fails', () async {
        // Arrange
        when(() => mockRepository.getAll())
            .thenAnswer((_) async => const Err(
                  TWMTDatabaseException('Database error'),
                ));

        // Act
        final result = await service.getAllSettings();

        // Assert
        expect(result.isErr, true);
      });
    });
  });
}
