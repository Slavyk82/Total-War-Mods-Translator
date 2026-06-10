import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Characterisation tests for DeepLProvider. Unlike OpenAI, DeepL is a pure
// machine-translation API (single /translate endpoint, character-based
// pricing, 403 for auth, 456 for quota). These tests pin request shaping,
// response parsing, and DeepL-specific error-code mapping.
//
// DeepLProvider delegates HTTP to DeepLApiClient, which is itself a thin
// wrapper over Dio. We mock Dio directly (one layer deeper than the provider)
// so that (a) we don't re-exercise unrelated api-client classes in setUp,
// and (b) we still cover the full DeepLApiClient.handleDioException path
// since the provider funnels all requests through wrapRequest(). This
// mirrors OpenAiProvider's test strategy.

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({Map<String, String>? texts}) {
  return LlmRequest(
    requestId: 'req-deepl-1',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: 'deepl',
    maxTokens: 512,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _successResponse(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions: RequestOptions(path: '/translate'),
  );
}

// Stubs Dio.options so DeepLApiClient.updateBaseUrl() (which mutates
// _dio.options.baseUrl) doesn't explode on the mock.
void _stubDioOptions(_MockDio dio) {
  when(() => dio.options).thenReturn(BaseOptions(baseUrl: 'https://api.deepl.com/v2'));
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/translate'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('DeepLProvider.translate', () {
    test('parses a successful /translate response and forwards request '
        'details (endpoint, DeepL-Auth-Key header, text array + target_lang)',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // Realistic DeepL response body: translations array preserving input
      // order, each entry carrying text + detected_source_language.
      final successBody = <String, dynamic>{
        'translations': [
          {'detected_source_language': 'EN', 'text': 'Bonjour le monde'},
          {'detected_source_language': 'EN', 'text': 'Bon retour'},
        ],
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(successBody));

      final result = await provider.translate(request, 'deepl-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final response = result.value;
      expect(response.translations, {
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      expect(response.providerCode, 'deepl');
      expect(response.modelName, 'deepl');
      // DeepL reports character counts under inputTokens/totalTokens; output
      // is always 0 (DeepL charges only on source characters).
      expect(response.inputTokens, 'Hello world'.length + 'Welcome back'.length);
      expect(response.outputTokens, 0);
      expect(response.totalTokens, response.inputTokens);
      expect(response.finishReason, 'completed');
      expect(response.requestId, 'req-deepl-1');

      // Verify call shape: path, payload, auth header.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/translate');

      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['text'], isA<List>());
      final textList = payload['text'] as List;
      expect(textList, containsAll(<String>['Hello world', 'Welcome back']));
      expect(payload['target_lang'], 'FR');
      // DeepL-specific defaults injected by the api client.
      expect(payload['tag_handling'], 'xml');
      expect(payload['preserve_formatting'], true);

      final options = captured[2] as Options;
      expect(
        options.headers,
        containsPair('Authorization', 'DeepL-Auth-Key deepl-test-key'),
      );
    });

    test('maps 429 response to LlmRateLimitException and propagates '
        'retry-after header as retryAfterSeconds', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/translate');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 429,
          requestOptions: requestOptions,
          headers: Headers.fromMap({
            'retry-after': ['12'],
          }),
          data: {'message': 'Too many requests'},
        ),
      ));

      final result = await provider.translate(request, 'deepl-test-key');

      expect(result.isErr, isTrue);
      final error = result.error;
      expect(error, isA<LlmRateLimitException>());
      final rateLimit = error as LlmRateLimitException;
      expect(rateLimit.retryAfterSeconds, 12);
      expect(rateLimit.providerCode, 'deepl');
    });

    test('maps 403 response to LlmAuthenticationException and does NOT retry '
        '(dio.post called exactly once). DeepL uses 403 for auth, not 401.',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/translate');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 403,
          requestOptions: requestOptions,
          data: {'message': 'Forbidden: invalid auth key'},
        ),
      ));

      final result = await provider.translate(request, 'bad-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.providerCode, 'deepl');
      // Key invariant: the provider itself does not retry auth failures.
      verify(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).called(1);
    });

    test('maps malformed response (missing translations field) to '
        'LlmResponseParseException instead of throwing', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // 200 OK but body lacks the required `translations` field. The
      // provider should wrap the resulting cast failure in a parse
      // exception rather than letting a TypeError bubble up.
      final malformedBody = <String, dynamic>{
        'message': 'ok but wrong shape',
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(malformedBody));

      final result = await provider.translate(request, 'deepl-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'deepl');
    });

    test('maps 456 response to LlmQuotaException (DeepL-specific code for '
        'character quota exhaustion)', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/translate');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 456,
          requestOptions: requestOptions,
          data: {'message': 'Quota exceeded'},
        ),
      ));

      final result = await provider.translate(request, 'deepl-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmQuotaException>());
      expect(result.error.providerCode, 'deepl');
    });

    test('maps 503 response to LlmServerException with statusCode preserved',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/translate');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 503,
          requestOptions: requestOptions,
          data: {'message': 'Service temporarily unavailable'},
        ),
      ));

      final result = await provider.translate(request, 'deepl-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
      final server = result.error as LlmServerException;
      expect(server.statusCode, 503);
      expect(server.providerCode, 'deepl');
    });

    test('forwards the caller-supplied CancelToken instance to dio.post so '
        'a user Stop aborts the in-flight request', () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();
      final token = CancelToken();

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(<String, dynamic>{
            'translations': [
              {'detected_source_language': 'EN', 'text': 'Bonjour'},
              {'detected_source_language': 'EN', 'text': 'Bon retour'},
            ],
          }));

      final result = await provider.translate(
        request,
        'deepl-test-key',
        cancelToken: token,
      );

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final captured = verify(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: captureAny(named: 'cancelToken'),
            options: any(named: 'options'),
          )).captured;
      expect(captured.single, same(token),
          reason: 'the exact CancelToken instance must reach Dio, '
              'otherwise CancelToken.cancel() cannot abort the request');
    });

    test('maps 400 response to LlmInvalidRequestException (covers DeepL '
        'payload-too-large / bad-request family: 400/413 both land here)',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // DeepL has no dedicated 413 branch in handleDioException; any
      // 4xx other than 403/404/429/456 funnels into LlmInvalidRequestException.
      // We exercise the canonical 400 path here.
      final requestOptions = RequestOptions(path: '/translate');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 400,
          requestOptions: requestOptions,
          data: {'message': 'Bad request: text parameter missing'},
        ),
      ));

      final result = await provider.translate(request, 'deepl-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.providerCode, 'deepl');
    });
  });

  // Regression tests for the DeepL-with-glossary cancellation path.
  //
  // translateWithGlossary used not to accept a cancelToken at all, and its
  // inner _apiClient.translate call omitted the token, so the one request
  // shape that goes through a synced glossary was uncancellable: pressing
  // Stop during a DeepL+glossary batch aborted every other provider request
  // but left this one running to completion. The token must be accepted and
  // forwarded to dio.post exactly like the standard translate path.
  group('DeepLProvider.translateWithGlossary', () {
    test('forwards the caller-supplied CancelToken instance to dio.post '
        '(glossary path must be cancellable like every other path)',
        () async {
      final dio = _MockDio();
      _stubDioOptions(dio);
      final provider = DeepLProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      // Glossary translation requires an explicit source language.
      final request = LlmRequest(
        requestId: 'req-deepl-glossary-1',
        targetLanguage: 'fr',
        texts: const {'ui_title': 'Hello world'},
        systemPrompt: 'Translate videogame UI strings.',
        modelName: 'deepl',
        sourceLanguage: 'en',
        glossaryId: 'local-glossary-1',
        maxTokens: 512,
        timestamp: DateTime(2026, 4, 14, 12, 0, 0),
      );
      final token = CancelToken();

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(<String, dynamic>{
            'translations': [
              {'detected_source_language': 'EN', 'text': 'Bonjour le monde'},
            ],
          }));

      final result = await provider.translateWithGlossary(
        request: request,
        apiKey: 'deepl-test-key',
        glossaryId: 'deepl-glossary-42',
        cancelToken: token,
      );

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');

      final captured = verify(() => dio.post(
            any(),
            data: captureAny(named: 'data'),
            cancelToken: captureAny(named: 'cancelToken'),
            options: any(named: 'options'),
          )).captured;
      final payload = captured[0] as Map<String, dynamic>;
      expect(payload['glossary_id'], 'deepl-glossary-42',
          reason: 'sanity: this is genuinely the glossary request shape');
      expect(captured[1], same(token),
          reason: 'the exact CancelToken instance must reach Dio on the '
              'glossary path — a user Stop must abort this request too');
    });
  });
}
