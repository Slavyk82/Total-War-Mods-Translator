import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_provider.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationProviderRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = TranslationProviderRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('TranslationProviderRepository', () {
    // Base timestamp kept small/constant to satisfy any timestamp CHECKs.
    const baseCreatedAt = 1000;

    TranslationProvider createTestProvider({
      String? id,
      String? code,
      String? name,
      String? apiEndpoint,
      String? defaultModel,
      int? maxContextTokens,
      int? maxBatchSize,
      int? rateLimitRpm,
      int? rateLimitTpm,
      bool? isActive,
      int? createdAt,
    }) {
      return TranslationProvider(
        id: id ?? 'provider-id',
        code: code ?? 'test-code',
        name: name ?? 'Test Provider',
        apiEndpoint: apiEndpoint,
        defaultModel: defaultModel,
        // CHECK (max_context_tokens IS NULL OR max_context_tokens > 0):
        // default to null so callers don't accidentally violate it.
        maxContextTokens: maxContextTokens,
        maxBatchSize: maxBatchSize ?? 30,
        rateLimitRpm: rateLimitRpm,
        rateLimitTpm: rateLimitTpm,
        isActive: isActive ?? true,
        createdAt: createdAt ?? baseCreatedAt,
      );
    }

    group('insert', () {
      test('should insert a provider successfully', () async {
        final provider = createTestProvider();

        final result = await repository.insert(provider);

        expect(result.isOk, isTrue);
        expect(result.value, equals(provider));

        // Verify it's in the database.
        final maps = await db.query(
          'translation_providers',
          where: 'id = ?',
          whereArgs: [provider.id],
        );
        expect(maps.length, equals(1));
        expect(maps.first['code'], equals('test-code'));
        expect(maps.first['name'], equals('Test Provider'));
        expect(maps.first['is_active'], equals(1));
      });

      test('should persist all optional fields', () async {
        final provider = createTestProvider(
          id: 'full',
          code: 'full-code',
          apiEndpoint: 'https://api.example.com/v1',
          defaultModel: 'model-x',
          maxContextTokens: 200000,
          maxBatchSize: 25,
          rateLimitRpm: 50,
          rateLimitTpm: 40000,
          isActive: false,
        );

        final result = await repository.insert(provider);

        expect(result.isOk, isTrue);

        final maps = await db.query(
          'translation_providers',
          where: 'id = ?',
          whereArgs: ['full'],
        );
        expect(maps.first['api_endpoint'], equals('https://api.example.com/v1'));
        expect(maps.first['default_model'], equals('model-x'));
        expect(maps.first['max_context_tokens'], equals(200000));
        expect(maps.first['max_batch_size'], equals(25));
        expect(maps.first['rate_limit_rpm'], equals(50));
        expect(maps.first['rate_limit_tpm'], equals(40000));
        expect(maps.first['is_active'], equals(0));
      });

      test('should fail when inserting duplicate ID', () async {
        final provider = createTestProvider();
        await repository.insert(provider);

        final duplicate = createTestProvider(code: 'different-code');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate code', () async {
        final provider1 = createTestProvider(id: 'p1', code: 'same-code');
        await repository.insert(provider1);

        final provider2 = createTestProvider(id: 'p2', code: 'same-code');
        final result = await repository.insert(provider2);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return provider when found', () async {
        final provider = createTestProvider();
        await repository.insert(provider);

        final result = await repository.getById(provider.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(provider.id));
        expect(result.value.code, equals(provider.code));
      });

      test('should return error when provider not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no providers exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all providers ordered by name ASC', () async {
        await repository.insert(
            createTestProvider(id: 'p1', code: 'c1', name: 'Zebra'));
        await repository.insert(
            createTestProvider(id: 'p2', code: 'c2', name: 'Apple'));
        await repository.insert(
            createTestProvider(id: 'p3', code: 'c3', name: 'Mango'));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].name, equals('Apple'));
        expect(result.value[1].name, equals('Mango'));
        expect(result.value[2].name, equals('Zebra'));
      });
    });

    group('update', () {
      test('should update provider successfully', () async {
        final provider = createTestProvider();
        await repository.insert(provider);

        final updated = provider.copyWith(name: 'Updated Name');
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.name, equals('Updated Name'));

        // Verify in database.
        final getResult = await repository.getById(provider.id);
        expect(getResult.value.name, equals('Updated Name'));
      });

      test('should toggle is_active on update', () async {
        final provider = createTestProvider(isActive: true);
        await repository.insert(provider);

        final updated = provider.copyWith(isActive: false);
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.isActive, isFalse);

        final maps = await db.query(
          'translation_providers',
          where: 'id = ?',
          whereArgs: [provider.id],
        );
        expect(maps.first['is_active'], equals(0));
      });

      test('should return error when provider not found', () async {
        final provider = createTestProvider(id: 'non-existent');

        final result = await repository.update(provider);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete provider successfully', () async {
        final provider = createTestProvider();
        await repository.insert(provider);

        final result = await repository.delete(provider.id);

        expect(result.isOk, isTrue);

        // Verify it's deleted.
        final getResult = await repository.getById(provider.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when provider not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByCode', () {
      test('should return provider when code found', () async {
        final provider = createTestProvider(code: 'anthropic');
        await repository.insert(provider);

        final result = await repository.getByCode('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value.code, equals('anthropic'));
        expect(result.value.id, equals(provider.id));
      });

      test('should return error when code not found', () async {
        final result = await repository.getByCode('non-existent-code');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getActive', () {
      test('should return empty list when no active providers exist', () async {
        // Only an inactive provider present.
        await repository.insert(
          createTestProvider(id: 'inactive', code: 'inactive', isActive: false),
        );

        final result = await repository.getActive();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return only active providers ordered by name ASC', () async {
        await repository.insert(createTestProvider(
            id: 'a1', code: 'a1', name: 'Zeta', isActive: true));
        await repository.insert(createTestProvider(
            id: 'a2', code: 'a2', name: 'Alpha', isActive: true));
        await repository.insert(createTestProvider(
            id: 'i1', code: 'i1', name: 'Beta', isActive: false));

        final result = await repository.getActive();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value.every((p) => p.isActive), isTrue);
        expect(result.value[0].name, equals('Alpha'));
        expect(result.value[1].name, equals('Zeta'));
      });
    });

    group('edge cases', () {
      test('should handle null optional fields round-trip', () async {
        final provider = createTestProvider(
          id: 'nulls',
          code: 'nulls',
          apiEndpoint: null,
          defaultModel: null,
          maxContextTokens: null,
          rateLimitRpm: null,
          rateLimitTpm: null,
        );

        final result = await repository.insert(provider);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById('nulls');
        expect(getResult.isOk, isTrue);
        expect(getResult.value.apiEndpoint, isNull);
        expect(getResult.value.defaultModel, isNull);
        expect(getResult.value.maxContextTokens, isNull);
        expect(getResult.value.rateLimitRpm, isNull);
        expect(getResult.value.rateLimitTpm, isNull);
      });

      test('should handle unicode in provider name', () async {
        final provider = createTestProvider(
          id: 'unicode',
          code: 'unicode',
          name: '中文 Provider 한국어',
        );

        final result = await repository.insert(provider);
        expect(result.isOk, isTrue);

        final getResult = await repository.getById('unicode');
        expect(getResult.value.name,
            equals('中文 Provider 한국어'));
      });
    });
  });
}
