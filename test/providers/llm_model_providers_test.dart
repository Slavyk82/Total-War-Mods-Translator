import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/config/settings_keys.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/providers/llm_model_providers.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart' as bridge;
import 'package:twmt/repositories/llm_provider_model_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../helpers/noop_logger.dart';
import '../helpers/test_database.dart';

class MockSettingsService extends Mock implements SettingsService {}

LlmProviderModel _model(
  String providerCode,
  String modelId, {
  required String displayName,
  bool isEnabled = false,
  bool isArchived = false,
}) {
  return LlmProviderModel(
    id: 'id-$modelId',
    providerCode: providerCode,
    modelId: modelId,
    displayName: displayName,
    isEnabled: isEnabled,
    isArchived: isArchived,
    createdAt: 0,
    updatedAt: 0,
    lastFetchedAt: 0,
  );
}

void main() {
  group('availableLlmModels', () {
    late Database db;
    late ProviderContainer container;

    setUp(() async {
      db = await TestDatabase.openMigrated();
      container = ProviderContainer(overrides: [
        // The real repository reads DatabaseService.database (wired by
        // openMigrated); availableLlmModels queries the table directly.
        bridge.llmProviderModelRepositoryProvider
            .overrideWithValue(LlmProviderModelRepository()),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
      ]);
    });

    tearDown(() async {
      container.dispose();
      await TestDatabase.close(db);
    });

    // Seed via raw insert (model.toJson maps bools to 0/1) to bypass the
    // repository's model-id validator and seed arbitrary providers.
    Future<void> seed(LlmProviderModel m) =>
        db.insert('llm_provider_models', m.toJson());

    test('returns only enabled, non-archived models ordered by provider then '
        'display name', () async {
      await seed(_model('openai', 'gpt-4', displayName: 'GPT-4', isEnabled: true));
      await seed(_model('anthropic', 'claude-3',
          displayName: 'Claude 3', isEnabled: true));
      // Excluded: disabled.
      await seed(_model('gemini', 'gemini-pro', displayName: 'Gemini'));
      // Excluded: archived (even though enabled).
      await seed(_model('deepseek', 'deepseek-chat',
          displayName: 'DeepSeek', isEnabled: true, isArchived: true));

      final models = await container.read(availableLlmModelsProvider.future);

      // anthropic < openai (provider_code ASC), then display_name ASC.
      expect(models.map((m) => m.modelId).toList(), ['claude-3', 'gpt-4']);
    });

    test('orders two models of the same provider by display name', () async {
      await seed(_model('anthropic', 'claude-sonnet',
          displayName: 'Z Sonnet', isEnabled: true));
      await seed(_model('anthropic', 'claude-opus',
          displayName: 'A Opus', isEnabled: true));

      final models = await container.read(availableLlmModelsProvider.future);

      expect(models.map((m) => m.modelId).toList(),
          ['claude-opus', 'claude-sonnet']);
    });

    test('returns an empty list when no models are enabled', () async {
      await seed(_model('gemini', 'gemini-pro', displayName: 'Gemini'));

      final models = await container.read(availableLlmModelsProvider.future);

      expect(models, isEmpty);
    });
  });

  group('SelectedLlmModel', () {
    late MockSettingsService mockService;
    late ProviderContainer container;

    setUp(() {
      mockService = MockSettingsService();
      when(() => mockService.getString(any(),
              defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => '');
      when(() => mockService.setString(any(), any()))
          .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

      container = ProviderContainer(overrides: [
        bridge.settingsServiceProvider.overrideWithValue(mockService),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
      ]);
    });

    tearDown(() => container.dispose());

    test('build() returns null before the persisted value loads', () {
      final value = container.read(selectedLlmModelProvider);
      expect(value, isNull);
    });

    test('restores the persisted model id on load', () async {
      when(() => mockService.getString(SettingsKeys.editorSelectedLlmModelId))
          .thenAnswer((_) async => 'm1');

      // Trigger build() then let _loadPersisted() resolve.
      container.read(selectedLlmModelProvider);
      await pumpEventQueue();

      expect(container.read(selectedLlmModelProvider), 'm1');
    });

    test('does not overwrite a selection set before the load resolves',
        () async {
      when(() => mockService.getString(SettingsKeys.editorSelectedLlmModelId))
          .thenAnswer((_) async => 'stored');

      final notifier = container.read(selectedLlmModelProvider.notifier);
      // Set a user choice before _loadPersisted's getString await resolves.
      notifier.setModel('user-choice');
      await pumpEventQueue();

      // The race guard (state == null) keeps the user choice.
      expect(container.read(selectedLlmModelProvider), 'user-choice');
    });

    test('setModel updates state and persists the id', () async {
      final notifier = container.read(selectedLlmModelProvider.notifier);

      notifier.setModel('gpt-4');
      await pumpEventQueue();

      expect(container.read(selectedLlmModelProvider), 'gpt-4');
      verify(() => mockService.setString(
          SettingsKeys.editorSelectedLlmModelId, 'gpt-4')).called(1);
    });

    test('seedDefaultIfEmpty only sets when state is null', () async {
      final notifier = container.read(selectedLlmModelProvider.notifier);
      await pumpEventQueue();

      notifier.seedDefaultIfEmpty('default-model');
      expect(container.read(selectedLlmModelProvider), 'default-model');

      // A second seed must NOT overwrite the existing selection.
      notifier.seedDefaultIfEmpty('other-model');
      expect(container.read(selectedLlmModelProvider), 'default-model');

      // seed never persists.
      verifyNever(() => mockService.setString(any(), any()));
    });

    test('clear nulls the state and persists an empty string', () async {
      final notifier = container.read(selectedLlmModelProvider.notifier);
      notifier.setModel('gpt-4');
      await pumpEventQueue();

      notifier.clear();
      await pumpEventQueue();

      expect(container.read(selectedLlmModelProvider), isNull);
      verify(() => mockService.setString(
          SettingsKeys.editorSelectedLlmModelId, '')).called(1);
    });
  });
}
