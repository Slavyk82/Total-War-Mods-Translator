import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/repositories/llm_provider_model_repository.dart';
import 'package:twmt/services/llm/llm_model_management_service.dart';

import '../../helpers/noop_logger.dart';

class MockLlmProviderModelRepository extends Mock
    implements LlmProviderModelRepository {}

LlmProviderModel _model({
  String id = 'm1',
  String providerCode = 'anthropic',
  bool isEnabled = false,
  bool isDefault = false,
  bool isArchived = false,
}) {
  return LlmProviderModel(
    id: id,
    providerCode: providerCode,
    modelId: 'claude',
    isEnabled: isEnabled,
    isDefault: isDefault,
    isArchived: isArchived,
    createdAt: 1,
    updatedAt: 1,
    lastFetchedAt: 1,
  );
}

void main() {
  late MockLlmProviderModelRepository repo;
  late LlmModelManagementService service;

  setUpAll(() {
    registerFallbackValue(_model());
  });

  setUp(() {
    repo = MockLlmProviderModelRepository();
    service = LlmModelManagementService(repo, NoopLogger());
  });

  String errMessage(Result result) => (result as Err).error.message;

  group('read-through getters', () {
    test('getModelsByProvider delegates to the repository', () async {
      final models = [_model()];
      when(() => repo.getByProvider('anthropic'))
          .thenAnswer((_) async => Ok(models));

      final result = await service.getModelsByProvider('anthropic');
      expect((result as Ok).value, same(models));
    });

    test('getEnabledModelsByProvider delegates', () async {
      when(() => repo.getEnabledByProvider('anthropic'))
          .thenAnswer((_) async => const Ok(<LlmProviderModel>[]));
      final result = await service.getEnabledModelsByProvider('anthropic');
      expect(result, isA<Ok>());
      verify(() => repo.getEnabledByProvider('anthropic')).called(1);
    });

    test('getAvailableModelsByProvider delegates', () async {
      when(() => repo.getAvailableByProvider('anthropic'))
          .thenAnswer((_) async => const Ok(<LlmProviderModel>[]));
      await service.getAvailableModelsByProvider('anthropic');
      verify(() => repo.getAvailableByProvider('anthropic')).called(1);
    });

    test('getDefaultModel delegates', () async {
      when(() => repo.getDefaultByProvider('anthropic'))
          .thenAnswer((_) async => Ok(_model(isDefault: true)));
      final result = await service.getDefaultModel('anthropic');
      expect((result as Ok).value, isNotNull);
    });

    test('getGlobalDefaultModel delegates', () async {
      when(() => repo.getGlobalDefault())
          .thenAnswer((_) async => const Ok(null));
      final result = await service.getGlobalDefaultModel();
      expect((result as Ok).value, isNull);
    });
  });

  group('enable / disable', () {
    test('enableModel returns Ok on success', () async {
      when(() => repo.enable('m1')).thenAnswer((_) async => const Ok(null));
      expect(await service.enableModel('m1'), isA<Ok>());
    });

    test('enableModel wraps repository errors', () async {
      when(() => repo.enable('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final result = await service.enableModel('m1');
      expect(errMessage(result), contains('Failed to enable model'));
    });

    test('disableModel wraps repository errors', () async {
      when(() => repo.disable('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final result = await service.disableModel('m1');
      expect(errMessage(result), contains('Failed to disable model'));
    });
  });

  group('setDefaultModel', () {
    test('sets default then enables the model', () async {
      when(() => repo.setAsDefault('m1'))
          .thenAnswer((_) async => const Ok(null));
      when(() => repo.enable('m1')).thenAnswer((_) async => const Ok(null));

      final result = await service.setDefaultModel('m1');

      expect(result, isA<Ok>());
      verify(() => repo.setAsDefault('m1')).called(1);
      verify(() => repo.enable('m1')).called(1);
    });

    test('wraps a setAsDefault failure and does not enable', () async {
      when(() => repo.setAsDefault('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));

      final result = await service.setDefaultModel('m1');

      expect(errMessage(result), contains('Failed to set default model'));
      verifyNever(() => repo.enable(any()));
    });
  });

  group('archiveModel', () {
    test('archives the model with cleared flags', () async {
      when(() => repo.getById('m1')).thenAnswer(
        (_) async => Ok(_model(isEnabled: true, isDefault: true)),
      );
      when(() => repo.update(any()))
          .thenAnswer((inv) async => Ok(inv.positionalArguments[0]));

      final result = await service.archiveModel('m1');
      expect(result, isA<Ok>());

      final updated =
          verify(() => repo.update(captureAny())).captured.single
              as LlmProviderModel;
      expect(updated.isArchived, isTrue);
      expect(updated.isEnabled, isFalse);
      expect(updated.isDefault, isFalse);
    });

    test('returns Err when the model is not found', () async {
      when(() => repo.getById('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('missing')));
      final result = await service.archiveModel('m1');
      expect(errMessage(result), contains('Model not found'));
      verifyNever(() => repo.update(any()));
    });

    test('wraps an update failure', () async {
      when(() => repo.getById('m1')).thenAnswer((_) async => Ok(_model()));
      when(() => repo.update(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final result = await service.archiveModel('m1');
      expect(errMessage(result), contains('Failed to archive model'));
    });

    test('catches an unexpected thrown error', () async {
      when(() => repo.getById('m1')).thenThrow(Exception('boom'));
      final result = await service.archiveModel('m1');
      expect(errMessage(result), contains('Unexpected error archiving model'));
    });
  });

  group('unarchiveModel', () {
    test('returns Ok on success', () async {
      when(() => repo.unarchive('m1')).thenAnswer((_) async => const Ok(null));
      expect(await service.unarchiveModel('m1'), isA<Ok>());
    });

    test('wraps repository errors', () async {
      when(() => repo.unarchive('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final result = await service.unarchiveModel('m1');
      expect(errMessage(result), contains('Failed to unarchive model'));
    });
  });

  group('resetProviderModels', () {
    test('returns the deleted count on success', () async {
      when(() => repo.deleteByProvider('anthropic'))
          .thenAnswer((_) async => const Ok(7));
      final result = await service.resetProviderModels('anthropic');
      expect((result as Ok).value, 7);
    });

    test('wraps repository errors', () async {
      when(() => repo.deleteByProvider('anthropic'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final result = await service.resetProviderModels('anthropic');
      expect(errMessage(result), contains('Failed to reset provider models'));
    });
  });

  group('getModelById', () {
    test('returns the model on success', () async {
      when(() => repo.getById('m1')).thenAnswer((_) async => Ok(_model()));
      final result = await service.getModelById('m1');
      expect((result as Ok).value.id, 'm1');
    });

    test('wraps repository errors', () async {
      when(() => repo.getById('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
      final result = await service.getModelById('m1');
      expect(errMessage(result), contains('Failed to get model'));
    });
  });

  group('toggleModelEnabled', () {
    test('disables an enabled model', () async {
      when(() => repo.getById('m1'))
          .thenAnswer((_) async => Ok(_model(isEnabled: true)));
      when(() => repo.disable('m1')).thenAnswer((_) async => const Ok(null));

      final result = await service.toggleModelEnabled('m1');

      expect(result, isA<Ok>());
      verify(() => repo.disable('m1')).called(1);
      verifyNever(() => repo.enable(any()));
    });

    test('enables a disabled model', () async {
      when(() => repo.getById('m1'))
          .thenAnswer((_) async => Ok(_model(isEnabled: false)));
      when(() => repo.enable('m1')).thenAnswer((_) async => const Ok(null));

      final result = await service.toggleModelEnabled('m1');

      expect(result, isA<Ok>());
      verify(() => repo.enable('m1')).called(1);
      verifyNever(() => repo.disable(any()));
    });

    test('returns Err when the model is not found', () async {
      when(() => repo.getById('m1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('missing')));
      final result = await service.toggleModelEnabled('m1');
      expect(errMessage(result), contains('Model not found'));
    });
  });
}
