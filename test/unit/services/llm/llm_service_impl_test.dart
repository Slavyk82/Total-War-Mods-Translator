import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/llm/llm_batch_adjuster.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/llm_service_impl.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockFactory extends Mock implements LlmProviderFactory {}

class _MockProvider extends Mock implements ILlmProvider {}

class _MockAdjuster extends Mock implements LlmBatchAdjuster {}

class _MockSettings extends Mock implements SettingsService {}

class _MockStorage extends Mock implements FlutterSecureStorage {}

LlmRequest _request({String? providerCode}) => LlmRequest(
      requestId: 'r1',
      targetLanguage: 'fr',
      texts: const {'k1': 'Hello'},
      systemPrompt: 'sys',
      providerCode: providerCode,
      timestamp: DateTime(2026, 1, 1),
    );

LlmResponse _response() => LlmResponse(
      requestId: 'r1',
      translations: const {'k1': 'Bonjour'},
      providerCode: 'anthropic',
      modelName: 'm',
      inputTokens: 1,
      outputTokens: 1,
      totalTokens: 2,
      processingTimeMs: 5,
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_request());
    registerFallbackValue(CancelToken());
  });

  late _MockFactory factory;
  late _MockProvider provider;
  late _MockAdjuster adjuster;
  late _MockSettings settings;
  late _MockStorage storage;
  late LlmServiceImpl service;

  setUp(() {
    factory = _MockFactory();
    provider = _MockProvider();
    adjuster = _MockAdjuster();
    settings = _MockSettings();
    storage = _MockStorage();
    service = LlmServiceImpl(
      providerFactory: factory,
      batchAdjuster: adjuster,
      settingsService: settings,
      secureStorage: storage,
      logging: FakeLogger(),
    );

    when(() => settings.getString(any(), defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => 'anthropic');
    when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => 'sk-key');
    when(() => factory.getProvider(any())).thenReturn(provider);
    when(() => factory.getAvailableProviders()).thenReturn(['anthropic', 'deepl']);
  });

  group('getActiveProviderCode', () {
    test('returns the stored provider code', () async {
      when(() => settings.getString(any(), defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => 'deepl');
      expect(await service.getActiveProviderCode(), 'deepl');
    });

    test('falls back to the default on an empty value', () async {
      when(() => settings.getString(any(), defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => '');
      expect(await service.getActiveProviderCode(), 'anthropic');
    });

    test('falls back to the default when settings throws', () async {
      when(() => settings.getString(any(), defaultValue: any(named: 'defaultValue')))
          .thenThrow(Exception('boom'));
      expect(await service.getActiveProviderCode(), 'anthropic');
    });
  });

  group('translateBatch', () {
    test('errors with an auth exception when the API key is missing', () async {
      when(() => storage.read(key: any(named: 'key'))).thenAnswer((_) async => '');

      final r = await service.translateBatch(_request());
      expect(r.unwrapErr(), isA<LlmAuthenticationException>());
    });

    test('returns the provider response on success', () async {
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(_response()));

      final r = await service.translateBatch(_request());
      expect(r.unwrap().translations['k1'], 'Bonjour');
    });

    test('propagates a provider error', () async {
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async =>
              Err(LlmProviderException('rate limit', providerCode: 'anthropic')));

      final r = await service.translateBatch(_request());
      expect(r.isErr, isTrue);
    });
  });

  group('estimateTokens', () {
    test('delegates to the batch adjuster', () async {
      when(() => adjuster.estimateTotalTokens(any())).thenReturn(123);
      expect((await service.estimateTokens(_request())).unwrap(), 123);
    });

    test('wraps an adjuster exception', () async {
      when(() => adjuster.estimateTotalTokens(any())).thenThrow(Exception('x'));
      expect((await service.estimateTokens(_request())).isErr, isTrue);
    });
  });

  group('validateApiKey', () {
    test('rejects an empty key', () async {
      final r = await service.validateApiKey('anthropic', '');
      expect(r.unwrapErr(), isA<LlmAuthenticationException>());
    });

    test('returns true when the provider validates the key', () async {
      when(() => provider.validateApiKey(any(), model: any(named: 'model')))
          .thenAnswer((_) async => const Ok(true));

      expect((await service.validateApiKey('anthropic', 'sk')).unwrap(), isTrue);
    });

    test('propagates a provider validation error', () async {
      when(() => provider.validateApiKey(any(), model: any(named: 'model')))
          .thenAnswer((_) async =>
              Err(LlmProviderException('bad key', providerCode: 'anthropic')));

      expect((await service.validateApiKey('anthropic', 'sk')).isErr, isTrue);
    });
  });

  group('setActiveProvider', () {
    test('rejects an unknown provider code', () async {
      final r = await service.setActiveProvider('unknown');
      expect(r.unwrapErr(), isA<LlmConfigurationException>());
    });

    test('persists a valid provider code', () async {
      when(() => settings.setString(any(), any()))
          .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

      final r = await service.setActiveProvider('deepl');
      expect(r.isOk, isTrue);
      verify(() => settings.setString(any(), 'deepl')).called(1);
    });
  });

  group('provider capability queries', () {
    test('supportsStreaming reflects the active provider', () async {
      when(() => provider.supportsStreaming).thenReturn(true);
      expect(await service.supportsStreaming(), isTrue);
    });

    test('getAvailableProviders delegates to the factory', () {
      expect(service.getAvailableProviders(), ['anthropic', 'deepl']);
    });

    test('isProviderAvailable is false for an unknown provider', () async {
      when(() => factory.hasProvider('ghost')).thenReturn(false);
      expect((await service.isProviderAvailable('ghost')).unwrap(), isFalse);
    });

    test('isProviderAvailable reflects a reachable provider', () async {
      when(() => factory.hasProvider('anthropic')).thenReturn(true);
      when(() => provider.isAvailable()).thenAnswer((_) async => const Ok(true));
      expect((await service.isProviderAvailable('anthropic')).unwrap(), isTrue);
    });
  });
}
