import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart'
    show TWMTDatabaseException;
import 'package:twmt/services/glossary/deepl_glossary_sync_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/llm_batch_adjuster.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/llm_service_impl.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockFactory extends Mock implements LlmProviderFactory {}

class _MockProvider extends Mock implements ILlmProvider {}

class _MockDeepLProvider extends Mock implements DeepLProvider {}

class _MockAdjuster extends Mock implements LlmBatchAdjuster {}

class _MockSettings extends Mock implements SettingsService {}

class _MockStorage extends Mock implements FlutterSecureStorage {}

class _MockGlossarySync extends Mock implements DeepLGlossarySyncService {}

class _StubGlossaryException extends GlossaryException {
  const _StubGlossaryException(super.message);
}

LlmRequest _request({
  String? providerCode,
  String? glossaryId,
  String? sourceLanguage,
  Map<String, String>? texts,
}) =>
    LlmRequest(
      requestId: 'r1',
      targetLanguage: 'fr',
      texts: texts ?? const {'k1': 'Hello'},
      systemPrompt: 'sys',
      providerCode: providerCode,
      glossaryId: glossaryId,
      sourceLanguage: sourceLanguage,
      timestamp: DateTime(2026, 1, 1),
    );

LlmResponse _response() => LlmResponse(
      requestId: 'r1',
      translations: const {'k1': 'Bonjour'},
      providerCode: 'deepl',
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

  LlmServiceImpl buildService({
    DeepLGlossarySyncService? Function()? glossaryFactory,
  }) =>
      LlmServiceImpl(
        providerFactory: factory,
        batchAdjuster: adjuster,
        settingsService: settings,
        secureStorage: storage,
        deeplGlossarySyncServiceFactory: glossaryFactory,
        logging: FakeLogger(),
      );

  setUp(() {
    factory = _MockFactory();
    provider = _MockProvider();
    adjuster = _MockAdjuster();
    settings = _MockSettings();
    storage = _MockStorage();
    service = buildService();

    when(() => settings.getString(any(),
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => 'anthropic');
    when(() => storage.read(key: any(named: 'key')))
        .thenAnswer((_) async => 'sk-key');
    when(() => factory.getProvider(any())).thenReturn(provider);
    when(() => factory.getAvailableProviders())
        .thenReturn(['anthropic', 'deepl']);
  });

  group('translateBatch error wrapping', () {
    test('wraps an unexpected (non-Llm) error as LlmServiceException', () async {
      when(() => factory.getProvider(any())).thenThrow(StateError('boom'));

      final r = await service.translateBatch(_request());
      final err = r.unwrapErr();
      expect(err, isA<LlmServiceException>());
      expect(err.message, contains('Failed to translate batch'));
    });

    test('rethrows an LlmServiceException raised mid-flight', () async {
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenThrow(LlmProviderException('explode', providerCode: 'x'));

      final r = await service.translateBatch(_request());
      expect(r.unwrapErr(), isA<LlmProviderException>());
    });

    test('uses the active provider when request has no providerCode', () async {
      when(() => settings.getString(any(),
              defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => 'anthropic');
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(_response()));

      final r = await service.translateBatch(_request());
      expect(r.isOk, isTrue);
      verify(() => factory.getProvider('anthropic')).called(1);
    });
  });

  group('translateBatch DeepL glossary path', () {
    late _MockDeepLProvider deepl;
    late _MockGlossarySync glossarySync;

    setUp(() {
      deepl = _MockDeepLProvider();
      glossarySync = _MockGlossarySync();
      when(() => factory.getProvider('deepl')).thenReturn(deepl);
      when(() => settings.getString(any(),
              defaultValue: any(named: 'defaultValue')))
          .thenAnswer((_) async => 'deepl');
      service = buildService(glossaryFactory: () => glossarySync);
    });

    LlmRequest deeplRequest() => _request(
          providerCode: 'deepl',
          glossaryId: 'g1',
          sourceLanguage: 'en',
        );

    test('translates with glossary when sync returns a DeepL glossary id',
        () async {
      when(() => glossarySync.ensureGlossarySynced(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Ok('deepl-gloss-1'));
      when(() => deepl.translateWithGlossary(
            request: any(named: 'request'),
            apiKey: any(named: 'apiKey'),
            glossaryId: any(named: 'glossaryId'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async => Ok(_response()));

      final r = await service.translateBatch(deeplRequest());
      expect(r.unwrap().translations['k1'], 'Bonjour');
      verify(() => deepl.translateWithGlossary(
            request: any(named: 'request'),
            apiKey: any(named: 'apiKey'),
            glossaryId: 'deepl-gloss-1',
            cancelToken: any(named: 'cancelToken'),
          )).called(1);
    });

    test('propagates a glossary translation error', () async {
      when(() => glossarySync.ensureGlossarySynced(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Ok('deepl-gloss-1'));
      when(() => deepl.translateWithGlossary(
            request: any(named: 'request'),
            apiKey: any(named: 'apiKey'),
            glossaryId: any(named: 'glossaryId'),
            cancelToken: any(named: 'cancelToken'),
          )).thenAnswer((_) async =>
              Err(LlmProviderException('deepl down', providerCode: 'deepl')));

      final r = await service.translateBatch(deeplRequest());
      expect(r.isErr, isTrue);
    });

    test('falls back to standard translation when sync fails', () async {
      when(() => glossarySync.ensureGlossarySynced(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer(
          (_) async => const Err(_StubGlossaryException('sync failed')));
      when(() => deepl.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(_response()));

      final r = await service.translateBatch(deeplRequest());
      expect(r.isOk, isTrue);
      verify(() => deepl.translate(any(), any(),
          cancelToken: any(named: 'cancelToken'))).called(1);
    });

    test('falls back to standard translation when no glossary id', () async {
      when(() => glossarySync.ensureGlossarySynced(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => const Ok<String?, GlossaryException>(null));
      when(() => deepl.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(_response()));

      final r = await service.translateBatch(deeplRequest());
      expect(r.isOk, isTrue);
      verify(() => deepl.translate(any(), any(),
          cancelToken: any(named: 'cancelToken'))).called(1);
    });

    test('wraps an exception thrown during glossary sync', () async {
      when(() => glossarySync.ensureGlossarySynced(
            glossaryId: any(named: 'glossaryId'),
            sourceLanguageCode: any(named: 'sourceLanguageCode'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenThrow(StateError('kaboom'));

      final r = await service.translateBatch(deeplRequest());
      final err = r.unwrapErr();
      expect(err, isA<LlmServiceException>());
      expect(err.message, contains('DeepL glossary'));
    });
  });

  group('translateBatchesParallel', () {
    test('yields a success result for each completed batch', () async {
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(_response()));

      final results = await service.translateBatchesParallel(
        [_request(), _request()],
        maxParallel: 2,
      ).toList();

      expect(results.length, 2);
      expect(results.every((r) => r.isOk), isTrue);
      final batch = results.first.unwrap();
      expect(batch.successfulUnits, 1);
      expect(batch.failedUnits, 0);
      expect(batch.totalTokens, 2);
    });

    test('emits a failed BatchTranslationResult when translateBatch errors',
        () async {
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async =>
              Err(LlmProviderException('nope', providerCode: 'anthropic')));

      final results = await service.translateBatchesParallel(
        [_request()],
      ).toList();

      expect(results.length, 1);
      final batch = results.first.unwrap();
      expect(batch.successfulUnits, 0);
      expect(batch.failedUnits, greaterThan(0));
      expect(batch.errors.isNotEmpty, isTrue);
    });

    test('clamps maxParallel below 1 up to a valid concurrency', () async {
      when(() => provider.translate(any(), any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(_response()));

      final results = await service
          .translateBatchesParallel([_request()], maxParallel: 0)
          .toList();

      expect(results.length, 1);
      expect(results.first.isOk, isTrue);
    });

    test('handles an empty request list', () async {
      final results =
          await service.translateBatchesParallel(const []).toList();
      expect(results, isEmpty);
    });
  });

  group('validateBatchSize / adjustBatchSize', () {
    test('validateBatchSize delegates to the adjuster', () async {
      when(() => adjuster.validateBatchSize(any(), any()))
          .thenAnswer((_) async => const Ok(true));

      final r = await service.validateBatchSize(_request());
      expect(r.unwrap(), isTrue);
    });

    test('validateBatchSize wraps a thrown error', () async {
      when(() => adjuster.validateBatchSize(any(), any()))
          .thenThrow(Exception('bad'));

      final r = await service.validateBatchSize(_request());
      expect(r.isErr, isTrue);
    });

    test('adjustBatchSize delegates to the adjuster', () async {
      when(() => adjuster.adjustBatchSize(any(), any()))
          .thenAnswer((_) async => Ok([_request()]));

      final r = await service.adjustBatchSize(_request());
      expect(r.unwrap().length, 1);
    });

    test('adjustBatchSize wraps a thrown error', () async {
      when(() => adjuster.adjustBatchSize(any(), any()))
          .thenThrow(Exception('bad'));

      final r = await service.adjustBatchSize(_request());
      expect(r.isErr, isTrue);
    });
  });

  group('validateApiKey extra branches', () {
    test('wraps an unexpected provider exception', () async {
      when(() => provider.validateApiKey(any(), model: any(named: 'model')))
          .thenThrow(Exception('weird'));

      final r = await service.validateApiKey('anthropic', 'sk');
      expect(r.unwrapErr(), isA<LlmServiceException>());
    });

    test('propagates an LlmConfigurationException directly', () async {
      when(() => provider.validateApiKey(any(), model: any(named: 'model')))
          .thenThrow(LlmConfigurationException('cfg', code: 'X'));

      final r = await service.validateApiKey('anthropic', 'sk');
      expect(r.unwrapErr(), isA<LlmConfigurationException>());
    });
  });

  group('setActiveProvider extra branches', () {
    test('wraps a settings save error as LlmServiceException', () async {
      when(() => settings.setString(any(), any())).thenThrow(Exception('io'));

      final r = await service.setActiveProvider('deepl');
      expect(r.unwrapErr(), isA<LlmServiceException>());
    });

    test('maps an Err settings result to a SETTINGS_ERROR exception', () async {
      when(() => settings.setString(any(), any())).thenAnswer((_) async =>
          Err<void, TWMTDatabaseException>(
              TWMTDatabaseException('disk full')));

      final r = await service.setActiveProvider('deepl');
      final err = r.unwrapErr();
      expect(err, isA<LlmServiceException>());
      expect(err.code, 'SETTINGS_ERROR');
    });
  });

  group('supportsStreaming', () {
    test('returns false when the provider lookup throws', () async {
      when(() => factory.getProvider(any())).thenThrow(StateError('x'));
      expect(await service.supportsStreaming(), isFalse);
    });
  });

  group('translateStreaming', () {
    test('errors when the provider does not support streaming', () async {
      when(() => provider.supportsStreaming).thenReturn(false);

      final results = await service.translateStreaming(_request()).toList();
      expect(results.single.unwrapErr(),
          isA<LlmUnsupportedOperationException>());
    });

    test('errors when the API key is missing', () async {
      when(() => provider.supportsStreaming).thenReturn(true);
      when(() => storage.read(key: any(named: 'key')))
          .thenAnswer((_) async => '');

      final results = await service.translateStreaming(_request()).toList();
      expect(results.single.unwrapErr(), isA<LlmAuthenticationException>());
    });

    test('streams ok and error chunks from the provider', () async {
      when(() => provider.supportsStreaming).thenReturn(true);
      when(() => provider.translateStreaming(any(), any())).thenAnswer(
        (_) => Stream.fromIterable([
          const Ok<String, LlmProviderException>('chunk-1'),
          Err<String, LlmProviderException>(
              LlmProviderException('mid', providerCode: 'anthropic')),
        ]),
      );

      final results = await service.translateStreaming(_request()).toList();
      expect(results.length, 2);
      expect(results[0].unwrap(), 'chunk-1');
      expect(results[1].isErr, isTrue);
    });

    test('wraps a thrown error during streaming', () async {
      when(() => provider.supportsStreaming).thenReturn(true);
      when(() => provider.translateStreaming(any(), any()))
          .thenThrow(StateError('boom'));

      final results = await service.translateStreaming(_request()).toList();
      expect(results.single.unwrapErr(), isA<LlmServiceException>());
    });
  });

  group('isProviderAvailable', () {
    test('returns false when the provider exists but is unreachable',
        () async {
      when(() => factory.hasProvider('anthropic')).thenReturn(true);
      when(() => provider.isAvailable()).thenAnswer((_) async =>
          Err(LlmProviderException('down', providerCode: 'anthropic')));

      expect((await service.isProviderAvailable('anthropic')).unwrap(),
          isFalse);
    });

    test('returns false when an exception is thrown', () async {
      when(() => factory.hasProvider('anthropic')).thenReturn(true);
      when(() => provider.isAvailable()).thenThrow(StateError('x'));

      expect((await service.isProviderAvailable('anthropic')).unwrap(),
          isFalse);
    });
  });

  group('getProviderStats', () {
    test('returns an error when the database is not initialized', () async {
      // DatabaseService.database throws StateError when uninitialized,
      // which the method wraps into an LlmServiceException.
      final r = await service.getProviderStats('anthropic');
      expect(r.unwrapErr(), isA<LlmServiceException>());
    });
  });

  group('ProviderStatistics value object', () {
    test('computes success rate and total tokens', () {
      final stats = ProviderStatistics(
        providerCode: 'anthropic',
        totalRequests: 10,
        successfulRequests: 8,
        failedRequests: 2,
        totalInputTokens: 100,
        totalOutputTokens: 50,
        averageResponseTimeMs: 12.5,
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 1, 1),
      );

      expect(stats.successRate, closeTo(0.8, 1e-9));
      expect(stats.totalTokens, 150);
      expect(stats.toString(), contains('anthropic'));
      expect(stats.toString(), contains('80.0%'));
    });

    test('success rate is zero when there are no requests', () {
      final stats = ProviderStatistics(
        providerCode: 'deepl',
        totalRequests: 0,
        successfulRequests: 0,
        failedRequests: 0,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        averageResponseTimeMs: 0,
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 1, 1),
      );

      expect(stats.successRate, 0.0);
    });
  });
}
