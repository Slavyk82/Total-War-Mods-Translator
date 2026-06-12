import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Complementary characterisation tests for DeepLProvider, targeting the
// methods/branches the existing deepl_provider_test.dart does NOT exercise:
// the glossary surface (createGlossary / listGlossaries / deleteGlossary /
// getSupportedLanguages plus the translateWithGlossary success + validation
// branches), and the non-translate accessors (validateApiKey, estimateTokens,
// estimateRequestTokens, isAvailable, getRateLimitStatus, calculateRetryDelay,
// supportsStreaming/translateStreaming).
//
// As in the sibling test, DeepLProvider delegates HTTP to DeepLApiClient,
// which wraps Dio. We mock Dio directly so we still cover the full
// DeepLApiClient request shaping + handleDioException path. The right HTTP
// verb is stubbed per endpoint (post for /translate + /glossaries create,
// get for /usage + /languages + /glossaries list, delete for glossary
// removal).

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({
  Map<String, String>? texts,
  String? sourceLanguage,
}) {
  return LlmRequest(
    requestId: 'req-deepl-more-1',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: 'deepl',
    sourceLanguage: sourceLanguage,
    maxTokens: 512,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _response(
  dynamic body, {
  int statusCode = 200,
  String path = '/translate',
}) {
  return Response<dynamic>(
    data: body,
    statusCode: statusCode,
    requestOptions: RequestOptions(path: path),
  );
}

DioException _dioError({
  required int statusCode,
  String path = '/translate',
  Map<String, dynamic>? data,
}) {
  final requestOptions = RequestOptions(path: path);
  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      statusCode: statusCode,
      requestOptions: requestOptions,
      data: data ?? {'message': 'error'},
    ),
  );
}

// Stubs Dio.options so DeepLApiClient.updateBaseUrl() (which mutates
// _dio.options.baseUrl) doesn't explode on the mock.
void _stubDioOptions(_MockDio dio) {
  when(() => dio.options)
      .thenReturn(BaseOptions(baseUrl: 'https://api.deepl.com/v2'));
}

DeepLProvider _provider(_MockDio dio) {
  return DeepLProvider(
    dio: dio,
    tokenCalculator: FakeTokenCalculator(),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/translate'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  // ===========================================================================
  // Non-translate accessors / pure helpers
  // ===========================================================================

  group('DeepLProvider non-HTTP helpers', () {
    test('estimateTokens returns the character count of the text (DeepL is '
        'character-priced, so 1 char == 1 unit)', () {
      final provider = _provider(_MockDio());
      // FakeTokenCalculator.calculateCharacterCount sums value lengths; the
      // provider passes {' ': text}, so the result is text.length.
      expect(provider.estimateTokens('Hello world'), 'Hello world'.length);
      expect(provider.estimateTokens(''), 0);
    });

    test('estimateRequestTokens returns total source character count across '
        'all texts', () {
      final provider = _provider(_MockDio());
      final request = _buildRequest();
      final expected =
          'Hello world'.length + 'Welcome back'.length;
      expect(provider.estimateRequestTokens(request), expected);
    });

    test('supportsStreaming is false and translateStreaming throws '
        'LlmUnsupportedOperationException (DeepL has no streaming endpoint)',
        () {
      final provider = _provider(_MockDio());
      expect(provider.supportsStreaming, isFalse);
      expect(
        () => provider.translateStreaming(_buildRequest(), 'k'),
        throwsA(isA<LlmUnsupportedOperationException>().having(
          (e) => e.operation,
          'operation',
          'translateStreaming',
        )),
      );
    });

    test('calculateRetryDelay uses retryAfterSeconds when present', () {
      final provider = _provider(_MockDio());
      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException(
          'rate limited',
          providerCode: 'deepl',
          retryAfterSeconds: 7,
        ),
      );
      expect(delay, const Duration(seconds: 7));
    });

    test('calculateRetryDelay falls back to 60s when retryAfterSeconds is null',
        () {
      final provider = _provider(_MockDio());
      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException(
          'rate limited',
          providerCode: 'deepl',
        ),
      );
      expect(delay, const Duration(seconds: 60));
    });

    test('provider metadata: providerCode/providerName are the DeepL constants',
        () {
      final provider = _provider(_MockDio());
      expect(provider.providerCode, 'deepl');
      expect(provider.providerName, 'DeepL');
    });
  });

  // ===========================================================================
  // validateApiKey -> GET /usage
  // ===========================================================================

  group('DeepLProvider.validateApiKey', () {
    test('returns Ok(true) when GET /usage answers 200', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _response(
            {'character_count': 10, 'character_limit': 500000},
            path: '/usage',
          ));

      final result = await provider.validateApiKey('deepl-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value, isTrue);

      final captured = verify(() => dio.get(
            captureAny(),
            options: any(named: 'options'),
          )).captured;
      expect(captured.single, '/usage');
    });

    test('maps a 403 from GET /usage to LlmAuthenticationException', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 403, path: '/usage'));

      final result = await provider.validateApiKey('bad-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.providerCode, 'deepl');
    });
  });

  // ===========================================================================
  // isAvailable -> GET /usage (validateStatus accepts non-2xx)
  // ===========================================================================

  group('DeepLProvider.isAvailable', () {
    test('returns Ok(true) when the availability probe returns <500 '
        '(even a 403 means the service is reachable)', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async =>
              _response(<String, dynamic>{}, statusCode: 403, path: '/usage'));

      final result = await provider.isAvailable();

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value, isTrue);
    });

    test('returns Ok(false) when the probe returns a 5xx', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async =>
              _response(<String, dynamic>{}, statusCode: 503, path: '/usage'));

      final result = await provider.isAvailable();

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value, isFalse);
    });

    test('maps a thrown DioException to Err(LlmNetworkException)', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: '/usage'),
        type: DioExceptionType.connectionError,
        message: 'host unreachable',
      ));

      final result = await provider.isAvailable();

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.providerCode, 'deepl');
    });
  });

  // ===========================================================================
  // getRateLimitStatus -> GET /usage parsed into RateLimitStatus
  // ===========================================================================

  group('DeepLProvider.getRateLimitStatus', () {
    test('parses character_count/character_limit into RateLimitStatus '
        '(remaining = limit - count)', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _response(
            {'character_count': 120000, 'character_limit': 500000},
            path: '/usage',
          ));

      final result = await provider.getRateLimitStatus('deepl-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final status = result.value as RateLimitStatus;
      expect(status.remainingTokens, 500000 - 120000);
      expect(status.totalTokens, 500000);
    });

    test('returns Ok(null) when usage body lacks character fields', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async =>
              _response(<String, dynamic>{'foo': 'bar'}, path: '/usage'));

      final result = await provider.getRateLimitStatus('deepl-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value, isNull);
    });

    test('maps a 429 from GET /usage to LlmRateLimitException', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 429, path: '/usage'));

      final result = await provider.getRateLimitStatus('deepl-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmRateLimitException>());
    });
  });

  // ===========================================================================
  // createGlossary -> POST /glossaries
  // ===========================================================================

  group('DeepLProvider.createGlossary', () {
    test('POSTs /glossaries with TSV entries + mapped target_lang and returns '
        'the new glossary_id', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _response(
            {'glossary_id': 'gl-created-99', 'name': 'Game terms'},
            path: '/glossaries',
          ));

      final result = await provider.createGlossary(
        apiKey: 'deepl-test-key',
        name: 'Game terms',
        targetLang: 'fr',
        entries: const {'Empire': 'Empire', 'Sword': 'Epee'},
      );

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value, 'gl-created-99');

      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/glossaries');

      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['name'], 'Game terms');
      // DeepLLanguageMapper upper-cases the language code.
      expect(payload['target_lang'], 'FR');
      expect(payload['entries_format'], 'tsv');
      // Entries are serialised as tab-separated key\tvalue lines.
      expect(payload['entries'], 'Empire\tEmpire\nSword\tEpee');

      final options = captured[2] as Options;
      expect(
        options.headers,
        containsPair('Authorization', 'DeepL-Auth-Key deepl-test-key'),
      );
    });

    test('maps a 400 from POST /glossaries to LlmInvalidRequestException',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 400, path: '/glossaries'));

      final result = await provider.createGlossary(
        apiKey: 'deepl-test-key',
        name: 'Bad',
        targetLang: 'fr',
        entries: const {'a': 'b'},
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.providerCode, 'deepl');
    });
  });

  // ===========================================================================
  // listGlossaries -> GET /glossaries
  // ===========================================================================

  group('DeepLProvider.listGlossaries', () {
    test('parses the glossaries array out of the response body', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _response(
            {
              'glossaries': [
                {'glossary_id': 'gl-1', 'name': 'A', 'target_lang': 'fr'},
                {'glossary_id': 'gl-2', 'name': 'B', 'target_lang': 'de'},
              ],
            },
            path: '/glossaries',
          ));

      final result = await provider.listGlossaries(apiKey: 'deepl-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final glossaries = result.value;
      expect(glossaries, hasLength(2));
      expect(glossaries[0]['glossary_id'], 'gl-1');
      expect(glossaries[1]['name'], 'B');

      final captured = verify(() => dio.get(
            captureAny(),
            options: any(named: 'options'),
          )).captured;
      expect(captured.single, '/glossaries');
    });

    test('maps a 403 from GET /glossaries to LlmAuthenticationException',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 403, path: '/glossaries'));

      final result = await provider.listGlossaries(apiKey: 'bad-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
    });
  });

  // ===========================================================================
  // deleteGlossary -> DELETE /glossaries/{id}
  // ===========================================================================

  group('DeepLProvider.deleteGlossary', () {
    test('issues DELETE /glossaries/{id} with the auth header and returns Ok',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.delete(
            any(),
            options: any(named: 'options'),
          )).thenAnswer((_) async =>
              _response(<String, dynamic>{}, statusCode: 204, path: '/glossaries/gl-1'));

      final result = await provider.deleteGlossary(
        apiKey: 'deepl-test-key',
        glossaryId: 'gl-1',
      );

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');

      final captured = verify(() => dio.delete(
            captureAny(),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/glossaries/gl-1');
      final options = captured[1] as Options;
      expect(
        options.headers,
        containsPair('Authorization', 'DeepL-Auth-Key deepl-test-key'),
      );
    });

    test('maps a 404 from DELETE /glossaries/{id} to '
        'LlmInvalidRequestException (DeepL 404 -> invalid request)', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.delete(
            any(),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 404, path: '/glossaries/missing'));

      final result = await provider.deleteGlossary(
        apiKey: 'deepl-test-key',
        glossaryId: 'missing',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
    });
  });

  // ===========================================================================
  // translateWithGlossary -> validation branch + success parse
  // ===========================================================================

  group('DeepLProvider.translateWithGlossary', () {
    test('returns LlmInvalidRequestException without any HTTP call when '
        'sourceLanguage is missing (glossary requires source_lang)', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);
      // No sourceLanguage set.
      final request = _buildRequest(texts: const {'ui_title': 'Hello world'});

      final result = await provider.translateWithGlossary(
        request: request,
        apiKey: 'deepl-test-key',
        glossaryId: 'gl-1',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, contains('source_lang'));
      // Validation short-circuits before reaching Dio.
      verifyNever(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          ));
    });

    test('success path sends source_lang + target_lang + glossary_id and '
        'parses translations back to the original keys', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);
      final request = _buildRequest(
        texts: const {'ui_title': 'Hello world'},
        sourceLanguage: 'en',
      );

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _response({
            'translations': [
              {'detected_source_language': 'EN', 'text': 'Bonjour le monde'},
            ],
          }));

      final result = await provider.translateWithGlossary(
        request: request,
        apiKey: 'deepl-test-key',
        glossaryId: 'gl-42',
      );

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value.translations, {'ui_title': 'Bonjour le monde'});
      expect(result.value.providerCode, 'deepl');

      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).captured;
      expect(captured[0], '/translate');
      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['source_lang'], 'EN');
      expect(payload['target_lang'], 'FR');
      expect(payload['glossary_id'], 'gl-42');
    });

    test('maps a 456 quota error on the glossary translate path to '
        'LlmQuotaException', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);
      final request = _buildRequest(
        texts: const {'ui_title': 'Hello world'},
        sourceLanguage: 'en',
      );

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 456));

      final result = await provider.translateWithGlossary(
        request: request,
        apiKey: 'deepl-test-key',
        glossaryId: 'gl-42',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmQuotaException>());
    });
  });

  // ===========================================================================
  // getSupportedLanguages -> two GET /languages calls (source + target)
  // ===========================================================================

  group('DeepLProvider.getSupportedLanguages', () {
    test('fetches source + target language lists and returns them keyed by '
        'role', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      // The provider issues two GET /languages calls differing only by the
      // `type` query param. Distinguish them on that param so each returns the
      // right list.
      when(() => dio.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((invocation) async {
        final query = invocation.namedArguments[#queryParameters]
            as Map<String, dynamic>?;
        final type = query?['type'] as String?;
        if (type == 'source') {
          return _response(
            [
              {'language': 'EN', 'name': 'English'},
              {'language': 'DE', 'name': 'German'},
            ],
            path: '/languages',
          );
        }
        return _response(
          [
            {'language': 'FR', 'name': 'French'},
            {'language': 'ES', 'name': 'Spanish'},
          ],
          path: '/languages',
        );
      });

      final result =
          await provider.getSupportedLanguages(apiKey: 'deepl-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      expect(result.value['source'], ['EN', 'DE']);
      expect(result.value['target'], ['FR', 'ES']);
    });

    test('maps a 500 from GET /languages to LlmServerException', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = _provider(dio);

      when(() => dio.get(
            any(),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenThrow(_dioError(statusCode: 500, path: '/languages'));

      final result =
          await provider.getSupportedLanguages(apiKey: 'deepl-test-key');

      expect(result.isErr, isTrue);
      final error = result.error;
      expect(error, isA<LlmServerException>());
      expect((error as LlmServerException).statusCode, 500);
    });
  });
}
