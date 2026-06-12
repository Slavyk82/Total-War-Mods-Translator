import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/repositories/llm_provider_model_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late LlmProviderModelRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = LlmProviderModelRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('LlmProviderModelRepository', () {
    final baseTimestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    LlmProviderModel createTestModel({
      String? id,
      String? providerCode,
      String? modelId,
      String? displayName,
      bool isEnabled = false,
      bool isDefault = false,
      bool isArchived = false,
      int? createdAt,
      int? updatedAt,
      int? lastFetchedAt,
    }) {
      return LlmProviderModel(
        id: id ?? 'model-id',
        providerCode: providerCode ?? 'anthropic',
        modelId: modelId ?? 'claude-sonnet-4-6',
        displayName: displayName,
        isEnabled: isEnabled,
        isDefault: isDefault,
        isArchived: isArchived,
        createdAt: createdAt ?? baseTimestamp,
        updatedAt: updatedAt ?? baseTimestamp,
        lastFetchedAt: lastFetchedAt ?? baseTimestamp,
      );
    }

    group('insert', () {
      test('should insert a model successfully', () async {
        final model = createTestModel(displayName: 'Claude Sonnet 4.6');

        final result = await repository.insert(model);

        expect(result.isOk, isTrue);
        expect(result.value, equals(model));

        final maps =
            await db.query('llm_provider_models', where: 'id = ?', whereArgs: [model.id]);
        expect(maps.length, equals(1));
        expect(maps.first['provider_code'], equals('anthropic'));
        expect(maps.first['model_id'], equals('claude-sonnet-4-6'));
        expect(maps.first['display_name'], equals('Claude Sonnet 4.6'));
      });

      test('should persist bool fields as integers', () async {
        final model = createTestModel(
          isEnabled: true,
          isDefault: true,
          isArchived: false,
        );

        final result = await repository.insert(model);
        expect(result.isOk, isTrue);

        final maps =
            await db.query('llm_provider_models', where: 'id = ?', whereArgs: [model.id]);
        expect(maps.first['is_enabled'], equals(1));
        expect(maps.first['is_default'], equals(1));
        expect(maps.first['is_archived'], equals(0));
      });

      test('should fail validation when provider code is empty', () async {
        final model = createTestModel(providerCode: '', modelId: 'some-model');

        final result = await repository.insert(model);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('Provider code cannot be empty'));
      });

      test('should fail validation when model id is empty', () async {
        final model = createTestModel(providerCode: 'openai', modelId: '');

        final result = await repository.insert(model);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('Model ID cannot be empty'));
      });

      test('should fail validation on cross-provider mismatch', () async {
        // A claude-* model with the openai provider is rejected.
        final model = createTestModel(
          providerCode: 'openai',
          modelId: 'claude-3-opus',
        );

        final result = await repository.insert(model);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('anthropic'));
      });

      test('should fail when inserting duplicate ID', () async {
        final model = createTestModel();
        await repository.insert(model);

        final duplicate = createTestModel(modelId: 'claude-opus-4-7');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail on duplicate provider_code + model_id', () async {
        final model1 = createTestModel(id: 'm1');
        await repository.insert(model1);

        // Same provider + model id, different primary key -> UNIQUE violation.
        final model2 = createTestModel(id: 'm2');
        final result = await repository.insert(model2);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return model when found', () async {
        final model = createTestModel();
        await repository.insert(model);

        final result = await repository.getById(model.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(model.id));
        expect(result.value.modelId, equals('claude-sonnet-4-6'));
      });

      test('should return error when model not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no models exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all models ordered by provider_code then model_id', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          providerCode: 'openai',
          modelId: 'gpt-5.5',
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          providerCode: 'anthropic',
          modelId: 'claude-opus-4-7',
        ));
        await repository.insert(createTestModel(
          id: 'm3',
          providerCode: 'anthropic',
          modelId: 'claude-sonnet-4-6',
        ));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        // anthropic before openai; within anthropic, claude-opus before claude-sonnet.
        expect(result.value[0].modelId, equals('claude-opus-4-7'));
        expect(result.value[1].modelId, equals('claude-sonnet-4-6'));
        expect(result.value[2].modelId, equals('gpt-5.5'));
      });
    });

    group('update', () {
      test('should update model successfully', () async {
        final model = createTestModel();
        await repository.insert(model);

        final updated = model.copyWith(displayName: 'New Display Name');
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.displayName, equals('New Display Name'));

        final getResult = await repository.getById(model.id);
        expect(getResult.value.displayName, equals('New Display Name'));
      });

      test('should fail validation on update with mismatched model', () async {
        final model = createTestModel();
        await repository.insert(model);

        final invalid = model.copyWith(providerCode: 'openai');
        final result = await repository.update(invalid);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('anthropic'));
      });

      test('should return error when model not found', () async {
        final model = createTestModel(id: 'non-existent');

        final result = await repository.update(model);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete model successfully', () async {
        final model = createTestModel();
        await repository.insert(model);

        final result = await repository.delete(model.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(model.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when model not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByProvider', () {
      test('should return only models for the given provider ordered by model_id', () async {
        await repository.insert(createTestModel(
          id: 'a2',
          providerCode: 'anthropic',
          modelId: 'claude-sonnet-4-6',
        ));
        await repository.insert(createTestModel(
          id: 'a1',
          providerCode: 'anthropic',
          modelId: 'claude-opus-4-7',
        ));
        await repository.insert(createTestModel(
          id: 'o1',
          providerCode: 'openai',
          modelId: 'gpt-5.5',
        ));

        final result = await repository.getByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].modelId, equals('claude-opus-4-7'));
        expect(result.value[1].modelId, equals('claude-sonnet-4-6'));
      });

      test('should return empty list for provider with no models', () async {
        final result = await repository.getByProvider('deepl');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getEnabledByProvider', () {
      test('should return only enabled non-archived models', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          modelId: 'claude-sonnet-4-6',
          isEnabled: true,
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          modelId: 'claude-opus-4-7',
          isEnabled: false,
        ));
        await repository.insert(createTestModel(
          id: 'm3',
          modelId: 'claude-haiku-4-5',
          isEnabled: true,
          isArchived: true,
        ));

        final result = await repository.getEnabledByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.id, equals('m1'));
      });

      test('should return empty list when none enabled', () async {
        await repository.insert(createTestModel(isEnabled: false));

        final result = await repository.getEnabledByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getAvailableByProvider', () {
      test('should return all non-archived models regardless of enabled', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          modelId: 'claude-sonnet-4-6',
          isEnabled: true,
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          modelId: 'claude-opus-4-7',
          isEnabled: false,
        ));
        await repository.insert(createTestModel(
          id: 'm3',
          modelId: 'claude-haiku-4-5',
          isArchived: true,
        ));

        final result = await repository.getAvailableByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(
          result.value.map((m) => m.id).toSet(),
          equals({'m1', 'm2'}),
        );
      });

      test('should return empty list when all archived', () async {
        await repository.insert(createTestModel(isArchived: true));

        final result = await repository.getAvailableByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getDefaultByProvider', () {
      test('should return the default non-archived model for provider', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          modelId: 'claude-sonnet-4-6',
          isDefault: true,
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          modelId: 'claude-opus-4-7',
          isDefault: false,
        ));

        final result = await repository.getDefaultByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals('m1'));
      });

      test('should return null when no default for provider', () async {
        await repository.insert(createTestModel(isDefault: false));

        final result = await repository.getDefaultByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });

      test('should not return an archived default', () async {
        await repository.insert(createTestModel(
          isDefault: true,
          isArchived: true,
        ));

        final result = await repository.getDefaultByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('getGlobalDefault', () {
      test('should return the global default across providers', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          providerCode: 'openai',
          modelId: 'gpt-5.5',
          isDefault: true,
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          providerCode: 'anthropic',
          modelId: 'claude-sonnet-4-6',
          isDefault: false,
        ));

        final result = await repository.getGlobalDefault();

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals('m1'));
      });

      test('should return null when no default exists', () async {
        await repository.insert(createTestModel(isDefault: false));

        final result = await repository.getGlobalDefault();

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });

      test('should ignore archived default', () async {
        await repository.insert(createTestModel(
          isDefault: true,
          isArchived: true,
        ));

        final result = await repository.getGlobalDefault();

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('getByProviderAndModelId', () {
      test('should return the matching model', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          providerCode: 'anthropic',
          modelId: 'claude-sonnet-4-6',
        ));

        final result =
            await repository.getByProviderAndModelId('anthropic', 'claude-sonnet-4-6');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals('m1'));
      });

      test('should return null when no match', () async {
        final result =
            await repository.getByProviderAndModelId('anthropic', 'claude-does-not-exist');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('upsertMany', () {
      test('should insert multiple new models', () async {
        final models = [
          createTestModel(
            id: 'm1',
            providerCode: 'anthropic',
            modelId: 'claude-sonnet-4-6',
          ),
          createTestModel(
            id: 'm2',
            providerCode: 'openai',
            modelId: 'gpt-5.5',
          ),
        ];

        final result = await repository.upsertMany(models);

        expect(result.isOk, isTrue);

        final all = await repository.getAll();
        expect(all.value.length, equals(2));
      });

      test('should replace existing model with same id', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          modelId: 'claude-sonnet-4-6',
          displayName: 'Original',
        ));

        final updated = [
          createTestModel(
            id: 'm1',
            modelId: 'claude-sonnet-4-6',
            displayName: 'Replaced',
          ),
        ];

        final result = await repository.upsertMany(updated);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('m1');
        expect(getResult.value.displayName, equals('Replaced'));

        final all = await repository.getAll();
        expect(all.value.length, equals(1));
      });

      test('should fail fast on an invalid model in the batch', () async {
        final models = [
          createTestModel(
            id: 'm1',
            providerCode: 'anthropic',
            modelId: 'claude-sonnet-4-6',
          ),
          createTestModel(
            id: 'm2',
            providerCode: 'openai',
            modelId: 'claude-3-opus', // mismatch
          ),
        ];

        final result = await repository.upsertMany(models);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('Invalid model in batch'));

        // No rows committed because validation happens before the transaction.
        final all = await repository.getAll();
        expect(all.value, isEmpty);
      });

      test('should succeed with an empty list', () async {
        final result = await repository.upsertMany([]);

        expect(result.isOk, isTrue);
        final all = await repository.getAll();
        expect(all.value, isEmpty);
      });
    });

    group('archiveStaleModels', () {
      test('should archive models not fetched since the timestamp', () async {
        await repository.insert(createTestModel(
          id: 'stale',
          modelId: 'claude-opus-4-7',
          isEnabled: true,
          isDefault: true,
          lastFetchedAt: 1000,
        ));
        await repository.insert(createTestModel(
          id: 'fresh',
          modelId: 'claude-sonnet-4-6',
          isEnabled: true,
          lastFetchedAt: 5000,
        ));

        final result = await repository.archiveStaleModels('anthropic', 2000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(1));

        final stale = await repository.getById('stale');
        expect(stale.value.isArchived, isTrue);
        expect(stale.value.isEnabled, isFalse);
        expect(stale.value.isDefault, isFalse);

        final fresh = await repository.getById('fresh');
        expect(fresh.value.isArchived, isFalse);
      });

      test('should not re-archive already archived models', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          modelId: 'claude-opus-4-7',
          isArchived: true,
          lastFetchedAt: 1000,
        ));

        final result = await repository.archiveStaleModels('anthropic', 2000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });

      test('should return 0 when nothing is stale', () async {
        await repository.insert(createTestModel(lastFetchedAt: 9999));

        final result = await repository.archiveStaleModels('anthropic', 2000);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });

    group('unarchive', () {
      test('should unarchive an archived model', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          isArchived: true,
        ));

        final result = await repository.unarchive('m1');

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('m1');
        expect(getResult.value.isArchived, isFalse);
      });

      test('should return error when model not found', () async {
        final result = await repository.unarchive('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('setAsDefault', () {
      test('should set a model as the global default', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          modelId: 'claude-sonnet-4-6',
          isDefault: false,
        ));

        final result = await repository.setAsDefault('m1');

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('m1');
        expect(getResult.value.isDefault, isTrue);
      });

      test('should clear previous default across all providers', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          providerCode: 'openai',
          modelId: 'gpt-5.5',
          isDefault: true,
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          providerCode: 'anthropic',
          modelId: 'claude-sonnet-4-6',
          isDefault: false,
        ));

        final result = await repository.setAsDefault('m2');

        expect(result.isOk, isTrue);

        final old = await repository.getById('m1');
        expect(old.value.isDefault, isFalse);

        final current = await repository.getById('m2');
        expect(current.value.isDefault, isTrue);

        // Exactly one default remains globally.
        final defaults = await db.query(
          'llm_provider_models',
          where: 'is_default = 1',
        );
        expect(defaults.length, equals(1));
        expect(defaults.first['id'], equals('m2'));
      });

      test('should return error when model not found', () async {
        final result = await repository.setAsDefault('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });

      test('should return error when setting an archived model as default', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          isArchived: true,
        ));

        final result = await repository.setAsDefault('m1');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('archived'));
      });
    });

    group('enable', () {
      test('should enable a model', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          isEnabled: false,
        ));

        final result = await repository.enable('m1');

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('m1');
        expect(getResult.value.isEnabled, isTrue);
      });

      test('should return error when model not found', () async {
        final result = await repository.enable('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });

      test('should return error when enabling an archived model', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          isArchived: true,
          isEnabled: false,
        ));

        final result = await repository.enable('m1');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('archived'));
      });
    });

    group('disable', () {
      test('should disable a model', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          isEnabled: true,
        ));

        final result = await repository.disable('m1');

        expect(result.isOk, isTrue);

        final getResult = await repository.getById('m1');
        expect(getResult.value.isEnabled, isFalse);
      });

      test('should return error when model not found', () async {
        final result = await repository.disable('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('deleteByProvider', () {
      test('should delete all models for a provider and return the count', () async {
        await repository.insert(createTestModel(
          id: 'm1',
          providerCode: 'anthropic',
          modelId: 'claude-sonnet-4-6',
        ));
        await repository.insert(createTestModel(
          id: 'm2',
          providerCode: 'anthropic',
          modelId: 'claude-opus-4-7',
        ));
        await repository.insert(createTestModel(
          id: 'm3',
          providerCode: 'openai',
          modelId: 'gpt-5.5',
        ));

        final result = await repository.deleteByProvider('anthropic');

        expect(result.isOk, isTrue);
        expect(result.value, equals(2));

        final remaining = await repository.getAll();
        expect(remaining.value.length, equals(1));
        expect(remaining.value.first.id, equals('m3'));
      });

      test('should return 0 when provider has no models', () async {
        final result = await repository.deleteByProvider('deepl');

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));
      });
    });
  });
}
