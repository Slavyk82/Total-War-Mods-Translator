import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart' as bridge;
import 'package:twmt/services/llm/llm_model_management_service.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../helpers/noop_logger.dart';

class MockLlmModelManagementService extends Mock
    implements LlmModelManagementService {}

class MockLlmProviderFactory extends Mock implements LlmProviderFactory {}

class MockLlmProvider extends Mock implements ILlmProvider {}

class MockSettingsService extends Mock implements SettingsService {}

/// Builds a minimal valid model for a provider.
LlmProviderModel _model(
  String providerCode,
  String modelId, {
  bool isEnabled = false,
  bool isDefault = false,
}) {
  return LlmProviderModel(
    id: 'id-$modelId',
    providerCode: providerCode,
    modelId: modelId,
    isEnabled: isEnabled,
    isDefault: isDefault,
    createdAt: 0,
    updatedAt: 0,
    lastFetchedAt: 0,
  );
}

/// Permissive stubs so a SettingsService-backed notifier `build()` can complete.
void _stubSettingsReads(MockSettingsService mock) {
  when(() => mock.getString(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => '');
  when(() => mock.getBool(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => true);
  when(() => mock.getInt(any(), defaultValue: any(named: 'defaultValue')))
      .thenAnswer((_) async => 500);
  when(() => mock.getPackPrefix()).thenAnswer((_) async => '!!!!!!!!!!');
  when(() => mock.setString(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  when(() => mock.setBool(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
  when(() => mock.setInt(any(), any()))
      .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));
}

void main() {
  // The exact channel the flutter_secure_storage MethodChannel platform
  // implementation talks to.
  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  /// Installs a secure-storage handler. [apiKey] is returned for 'read';
  /// pass null to simulate "no stored key".
  void installSecureStorage({String? apiKey}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          return apiKey;
        case 'write':
          return null;
        case 'readAll':
          return <String, String>{};
        case 'delete':
          return null;
        case 'deleteAll':
          return null;
        case 'containsKey':
          return apiKey != null;
        default:
          return null;
      }
    });
  }

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    // Default: no stored key. Individual groups/tests reinstall as needed.
    installSecureStorage(apiKey: null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  // ---------------------------------------------------------------------------
  group('llmModelManagementServiceProvider (bridge)', () {
    test('can be overridden with a mock', () {
      final mock = MockLlmModelManagementService();
      final container = ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(mock),
      ]);
      addTearDown(container.dispose);

      expect(container.read(llmModelManagementServiceProvider), same(mock));
    });
  });

  // ---------------------------------------------------------------------------
  group('LlmModels notifier - build()', () {
    late MockLlmModelManagementService service;
    late ProviderContainer container;

    setUp(() {
      service = MockLlmModelManagementService();
      container = ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
      ]);
    });

    tearDown(() => container.dispose());

    test('Ok -> returns the available models', () async {
      final models = [_model('anthropic', 'claude-a'), _model('anthropic', 'claude-b')];
      when(() => service.getAvailableModelsByProvider('anthropic'))
          .thenAnswer((_) async =>
              Ok<List<LlmProviderModel>, TWMTDatabaseException>(models));

      final result = await container.read(llmModelsProvider('anthropic').future);

      expect(result, models);
    });

    test('Err -> returns an empty list', () async {
      when(() => service.getAvailableModelsByProvider('anthropic')).thenAnswer(
          (_) async => const Err<List<LlmProviderModel>, TWMTDatabaseException>(
              TWMTDatabaseException('boom')));

      final result = await container.read(llmModelsProvider('anthropic').future);

      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('LlmModels notifier - enable/disable/toggle', () {
    late MockLlmModelManagementService service;
    late ProviderContainer container;

    setUp(() {
      service = MockLlmModelManagementService();
      // build() must complete for the notifier to be usable.
      when(() => service.getAvailableModelsByProvider(any()))
          .thenAnswer((_) async =>
              const Ok<List<LlmProviderModel>, TWMTDatabaseException>([]));
      container = ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
      ]);
    });

    tearDown(() => container.dispose());

    Future<LlmModels> notifier(String code) async {
      await container.read(llmModelsProvider(code).future);
      return container.read(llmModelsProvider(code).notifier);
    }

    test('enableModel Ok -> (true, null) and calls service.enableModel',
        () async {
      when(() => service.enableModel('m1'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));

      final result = await (await notifier('anthropic')).enableModel('m1');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      verify(() => service.enableModel('m1')).called(1);
    });

    test('enableModel Err -> (false, error.message)', () async {
      when(() => service.enableModel('m1')).thenAnswer((_) async =>
          const Err<void, ServiceException>(ServiceException('enable failed')));

      final result = await (await notifier('anthropic')).enableModel('m1');

      expect(result.$1, isFalse);
      expect(result.$2, 'enable failed');
    });

    test('disableModel Ok -> (true, null) and calls service.disableModel',
        () async {
      when(() => service.disableModel('m1'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));

      final result = await (await notifier('anthropic')).disableModel('m1');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      verify(() => service.disableModel('m1')).called(1);
    });

    test('disableModel Err -> (false, error.message)', () async {
      when(() => service.disableModel('m1')).thenAnswer((_) async =>
          const Err<void, ServiceException>(ServiceException('disable failed')));

      final result = await (await notifier('anthropic')).disableModel('m1');

      expect(result.$1, isFalse);
      expect(result.$2, 'disable failed');
    });

    test('toggleEnabled Ok -> (true, null) and calls service.toggleModelEnabled',
        () async {
      when(() => service.toggleModelEnabled('m1'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));

      final result = await (await notifier('anthropic')).toggleEnabled('m1');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      verify(() => service.toggleModelEnabled('m1')).called(1);
    });

    test('toggleEnabled Err -> (false, error.message)', () async {
      when(() => service.toggleModelEnabled('m1')).thenAnswer((_) async =>
          const Err<void, ServiceException>(ServiceException('toggle failed')));

      final result = await (await notifier('anthropic')).toggleEnabled('m1');

      expect(result.$1, isFalse);
      expect(result.$2, 'toggle failed');
    });
  });

  // ---------------------------------------------------------------------------
  group('LlmModels notifier - setAsDefault', () {
    late MockLlmModelManagementService service;
    late MockSettingsService settings;

    ProviderContainer buildContainer() {
      return ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
        // setAsDefault for non-deepl reads llmProviderSettings.notifier, whose
        // build() reads SettingsService + secure storage.
        settingsServiceProvider.overrideWithValue(settings),
      ]);
    }

    setUp(() {
      service = MockLlmModelManagementService();
      settings = MockSettingsService();
      _stubSettingsReads(settings);
      when(() => service.getAvailableModelsByProvider(any()))
          .thenAnswer((_) async =>
              const Ok<List<LlmProviderModel>, TWMTDatabaseException>([]));
    });

    test(
        'Ok non-deepl provider -> (true, null) and updates active provider '
        '(setString(activeProvider, code))', () async {
      installSecureStorage(apiKey: null); // LlmProviderSettings.build reads it
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => service.setDefaultModel('m1'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));

      await container.read(llmModelsProvider('anthropic').future);
      final result = await container
          .read(llmModelsProvider('anthropic').notifier)
          .setAsDefault('m1');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      verify(() => service.setDefaultModel('m1')).called(1);
      // updateActiveProvider(providerCode) -> setString(activeProvider, code).
      verify(() =>
              settings.setString(SettingsKeys.activeProvider, 'anthropic'))
          .called(1);
    });

    test(
        'Ok deepl provider -> (true, null) but does NOT update active provider',
        () async {
      installSecureStorage(apiKey: null);
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => service.setDefaultModel('m1'))
          .thenAnswer((_) async => const Ok<void, ServiceException>(null));

      await container.read(llmModelsProvider('deepl').future);
      final result = await container
          .read(llmModelsProvider('deepl').notifier)
          .setAsDefault('m1');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      verify(() => service.setDefaultModel('m1')).called(1);
      // DeepL is skipped as active provider.
      verifyNever(
          () => settings.setString(SettingsKeys.activeProvider, any()));
    });

    test('Err -> (false, error.message) and does not update active provider',
        () async {
      installSecureStorage(apiKey: null);
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => service.setDefaultModel('m1')).thenAnswer((_) async =>
          const Err<void, ServiceException>(
              ServiceException('set default failed')));

      await container.read(llmModelsProvider('anthropic').future);
      final result = await container
          .read(llmModelsProvider('anthropic').notifier)
          .setAsDefault('m1');

      expect(result.$1, isFalse);
      expect(result.$2, 'set default failed');
      verifyNever(
          () => settings.setString(SettingsKeys.activeProvider, any()));
    });
  });

  // ---------------------------------------------------------------------------
  group('enabledLlmModels provider', () {
    late MockLlmModelManagementService service;
    late ProviderContainer container;

    setUp(() {
      service = MockLlmModelManagementService();
      container = ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
      ]);
    });

    tearDown(() => container.dispose());

    test('Ok -> returns the enabled models', () async {
      final models = [_model('openai', 'gpt-x', isEnabled: true)];
      when(() => service.getEnabledModelsByProvider('openai'))
          .thenAnswer((_) async =>
              Ok<List<LlmProviderModel>, TWMTDatabaseException>(models));

      final result =
          await container.read(enabledLlmModelsProvider('openai').future);

      expect(result, models);
    });

    test('Err -> returns an empty list', () async {
      when(() => service.getEnabledModelsByProvider('openai')).thenAnswer(
          (_) async => const Err<List<LlmProviderModel>, TWMTDatabaseException>(
              TWMTDatabaseException('boom')));

      final result =
          await container.read(enabledLlmModelsProvider('openai').future);

      expect(result, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  group('defaultLlmModel provider', () {
    late MockLlmModelManagementService service;
    late ProviderContainer container;

    setUp(() {
      service = MockLlmModelManagementService();
      container = ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
      ]);
    });

    tearDown(() => container.dispose());

    test('Ok -> returns the default model', () async {
      final model = _model('openai', 'gpt-x', isDefault: true);
      when(() => service.getDefaultModel('openai')).thenAnswer((_) async =>
          Ok<LlmProviderModel?, TWMTDatabaseException>(model));

      final result =
          await container.read(defaultLlmModelProvider('openai').future);

      expect(result, model);
    });

    test('Err -> returns null', () async {
      when(() => service.getDefaultModel('openai')).thenAnswer((_) async =>
          const Err<LlmProviderModel?, TWMTDatabaseException>(
              TWMTDatabaseException('boom')));

      final result =
          await container.read(defaultLlmModelProvider('openai').future);

      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  group('LlmProviderSettings.testConnection', () {
    late MockLlmModelManagementService service;
    late MockSettingsService settings;
    late MockLlmProviderFactory factory;
    late MockLlmProvider provider;

    setUp(() {
      service = MockLlmModelManagementService();
      settings = MockSettingsService();
      _stubSettingsReads(settings);
      factory = MockLlmProviderFactory();
      provider = MockLlmProvider();
      when(() => provider.providerName).thenReturn('Mock Provider');
    });

    ProviderContainer buildContainer() {
      return ProviderContainer(overrides: [
        llmModelManagementServiceProvider.overrideWithValue(service),
        loggingServiceProvider.overrideWithValue(NoopLogger()),
        settingsServiceProvider.overrideWithValue(settings),
        bridge.llmProviderFactoryProvider.overrideWithValue(factory),
      ]);
    }

    Future<LlmProviderSettings> notifier(ProviderContainer container) async {
      await container.read(llmProviderSettingsProvider.future);
      return container.read(llmProviderSettingsProvider.notifier);
    }

    test('unknown provider -> (false, "Unknown provider")', () async {
      installSecureStorage(apiKey: null);
      final container = buildContainer();
      addTearDown(container.dispose);

      final result =
          await (await notifier(container)).testConnection('not-a-provider');

      expect(result.$1, isFalse);
      expect(result.$2, 'Unknown provider');
    });

    test('known provider, no API key -> (false, "No API key configured")',
        () async {
      installSecureStorage(apiKey: null); // secure storage read returns null
      final container = buildContainer();
      addTearDown(container.dispose);

      final result =
          await (await notifier(container)).testConnection('anthropic');

      expect(result.$1, isFalse);
      expect(result.$2, 'No API key configured');
    });

    test(
        'non-deepl, API key present, no enabled model -> '
        '(false, "No model enabled...")', () async {
      installSecureStorage(apiKey: 'sk-key');
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => service.getEnabledModelsByProvider('anthropic'))
          .thenAnswer((_) async =>
              const Ok<List<LlmProviderModel>, TWMTDatabaseException>([]));

      final result =
          await (await notifier(container)).testConnection('anthropic');

      expect(result.$1, isFalse);
      expect(
        result.$2,
        'No model enabled. Enable at least one model to test the connection.',
      );
    });

    test(
        'success: api key + enabled model + validateApiKey Ok -> (true, null)',
        () async {
      installSecureStorage(apiKey: 'sk-key');
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => service.getEnabledModelsByProvider('anthropic')).thenAnswer(
          (_) async => Ok<List<LlmProviderModel>, TWMTDatabaseException>(
              [_model('anthropic', 'claude-a', isEnabled: true)]));
      when(() => factory.getProvider('anthropic')).thenReturn(provider);
      when(() => provider.validateApiKey('sk-key', model: 'claude-a'))
          .thenAnswer(
              (_) async => const Ok<bool, LlmProviderException>(true));

      final result =
          await (await notifier(container)).testConnection('anthropic');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      verify(() => provider.validateApiKey('sk-key', model: 'claude-a'))
          .called(1);
    });

    test('failure: validateApiKey Err -> (false, error.message)', () async {
      installSecureStorage(apiKey: 'sk-key');
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => service.getEnabledModelsByProvider('anthropic')).thenAnswer(
          (_) async => Ok<List<LlmProviderModel>, TWMTDatabaseException>(
              [_model('anthropic', 'claude-a', isEnabled: true)]));
      when(() => factory.getProvider('anthropic')).thenReturn(provider);
      when(() => provider.validateApiKey('sk-key', model: 'claude-a'))
          .thenAnswer((_) async => const Err<bool, LlmProviderException>(
              LlmProviderException('invalid key', providerCode: 'anthropic')));

      final result =
          await (await notifier(container)).testConnection('anthropic');

      expect(result.$1, isFalse);
      expect(result.$2, 'invalid key');
    });

    test(
        'deepl path: api key present (skips enabled-model check), '
        'validateApiKey Ok -> (true, null)', () async {
      installSecureStorage(apiKey: 'dl-key');
      final container = buildContainer();
      addTearDown(container.dispose);

      when(() => factory.getProvider('deepl')).thenReturn(provider);
      // model is null for deepl (no enabled-model lookup).
      when(() => provider.validateApiKey('dl-key', model: null))
          .thenAnswer(
              (_) async => const Ok<bool, LlmProviderException>(true));

      final result =
          await (await notifier(container)).testConnection('deepl');

      expect(result.$1, isTrue);
      expect(result.$2, isNull);
      // DeepL must NOT consult the enabled-model service.
      verifyNever(() => service.getEnabledModelsByProvider(any()));
      verify(() => provider.validateApiKey('dl-key', model: null)).called(1);
    });
  });
}
