import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/glossary/deepl_glossary_sync_service.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/llm/llm_batch_adjuster.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/llm_service_impl.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for the DeepL-with-glossary cancellation path in
// LlmServiceImpl.translateBatch.
//
// The method receives a Dio CancelToken from the real translation flow
// (LlmRetryHandler passes it into every attempt). The two glossary FALLBACK
// branches always forwarded it to provider.translate, but the main success
// branch called provider.translateWithGlossary WITHOUT the token, so a user
// Stop during a DeepL+glossary batch left the HTTP request running to
// completion. The token instance must reach provider.translateWithGlossary.

class _MockProviderFactory extends Mock implements LlmProviderFactory {}

class _MockDeepLProvider extends Mock implements DeepLProvider {}

class _MockBatchAdjuster extends Mock implements LlmBatchAdjuster {}

class _MockSettingsService extends Mock implements SettingsService {}

class _MockSecureStorage extends Mock implements FlutterSecureStorage {}

class _MockGlossarySync extends Mock implements DeepLGlossarySyncService {}

LlmRequest _glossaryRequest() => LlmRequest(
      requestId: 'req-1',
      targetLanguage: 'fr',
      texts: const {'key_1': 'Hello'},
      systemPrompt: 'prompt',
      providerCode: 'deepl',
      sourceLanguage: 'en',
      glossaryId: 'local-glossary-1',
      maxTokens: 256,
      timestamp: DateTime(2026, 4, 14),
    );

LlmResponse _response() => LlmResponse(
      requestId: 'req-1',
      translations: const {'key_1': 'Bonjour'},
      providerCode: 'deepl',
      modelName: 'deepl',
      inputTokens: 5,
      outputTokens: 0,
      totalTokens: 5,
      processingTimeMs: 10,
      timestamp: DateTime(2026, 4, 14),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_glossaryRequest());
    registerFallbackValue(CancelToken());
  });

  late _MockProviderFactory factory;
  late _MockDeepLProvider provider;
  late _MockGlossarySync glossarySync;
  late LlmServiceImpl service;

  setUp(() {
    factory = _MockProviderFactory();
    provider = _MockDeepLProvider();
    glossarySync = _MockGlossarySync();
    final secureStorage = _MockSecureStorage();

    when(() => secureStorage.read(key: 'deepl_api_key'))
        .thenAnswer((_) async => 'deepl-test-key');
    when(() => factory.getProvider('deepl')).thenReturn(provider);

    service = LlmServiceImpl(
      providerFactory: factory,
      batchAdjuster: _MockBatchAdjuster(),
      settingsService: _MockSettingsService(),
      secureStorage: secureStorage,
      deeplGlossarySyncServiceFactory: () => glossarySync,
      logging: FakeLogger(),
    );
  });

  test(
      'translateBatch forwards the CancelToken instance to '
      'provider.translateWithGlossary on the DeepL glossary success path',
      () async {
    when(() => glossarySync.ensureGlossarySynced(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => const Ok('deepl-glossary-42'));

    when(() => provider.translateWithGlossary(
          request: any(named: 'request'),
          apiKey: any(named: 'apiKey'),
          glossaryId: any(named: 'glossaryId'),
          cancelToken: any(named: 'cancelToken'),
        )).thenAnswer((_) async => Ok(_response()));

    final token = CancelToken();
    final result =
        await service.translateBatch(_glossaryRequest(), cancelToken: token);

    expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');

    final captured = verify(() => provider.translateWithGlossary(
          request: any(named: 'request'),
          apiKey: any(named: 'apiKey'),
          glossaryId: captureAny(named: 'glossaryId'),
          cancelToken: captureAny(named: 'cancelToken'),
        )).captured;
    expect(captured[0], 'deepl-glossary-42',
        reason: 'sanity: the synced DeepL glossary id is used');
    expect(captured[1], same(token),
        reason: 'the exact token instance must be forwarded so a user Stop '
            'aborts the glossary request like every other translation path');
    // The glossary success branch must not silently fall back to the
    // non-glossary endpoint.
    verifyNever(() => provider.translate(any(), any(),
        cancelToken: any(named: 'cancelToken')));
  });

  test(
      'glossary sync failure falls back to provider.translate WITH the same '
      'CancelToken (fallback branch keeps the established contract)',
      () async {
    when(() => glossarySync.ensureGlossarySynced(
          glossaryId: any(named: 'glossaryId'),
          sourceLanguageCode: any(named: 'sourceLanguageCode'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer(
            (_) async => Err(DeepLGlossaryException('sync exploded')));

    when(() => provider.translate(any(), any(),
            cancelToken: any(named: 'cancelToken')))
        .thenAnswer((_) async => Ok(_response()));

    final token = CancelToken();
    final result =
        await service.translateBatch(_glossaryRequest(), cancelToken: token);

    expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');

    final captured = verify(() => provider.translate(any(), any(),
        cancelToken: captureAny(named: 'cancelToken'))).captured;
    expect(captured.single, same(token));
  });
}
