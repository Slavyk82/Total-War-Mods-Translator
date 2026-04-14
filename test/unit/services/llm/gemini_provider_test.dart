import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/gemini_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Characterisation tests for GeminiProvider. Covers request shaping,
// successful response parsing, and Dio error mapping. Gemini has a
// distinct API shape from OpenAI: contents/parts arrays, usageMetadata
// for tokens, and SAFETY finishReason for moderation.

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({Map<String, String>? texts}) {
  return LlmRequest(
    requestId: 'req-gem-42',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: 'gemini-3-flash-preview',
    maxTokens: 512,
    temperature: 0.2,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _successResponse(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions:
        RequestOptions(path: '/models/gemini-3-flash-preview:generateContent'),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(
        RequestOptions(path: '/models/gemini-3-flash-preview:generateContent'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('GeminiProvider.translate', () {
    test(
        'parses a successful :generateContent response and forwards request '
        'details (URL with model, x-goog-api-key header, contents payload)',
        () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // Gemini returns translations as text inside candidates[0].content
      // .parts[0].text. The provider then json-decodes the text into the
      // translations map; this body exercises the simple key-value branch
      // of _parseTranslations.
      final innerText = jsonEncode({
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      final successBody = <String, dynamic>{
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': innerText}
              ],
            },
            'finishReason': 'STOP',
            'safetyRatings': <Map<String, dynamic>>[],
          },
        ],
        'usageMetadata': {
          'promptTokenCount': 55,
          'candidatesTokenCount': 21,
          'totalTokenCount': 76,
        },
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(successBody));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final response = result.value;
      expect(response.translations, {
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      expect(response.modelName, 'gemini-3-flash-preview');
      expect(response.inputTokens, 55);
      expect(response.outputTokens, 21);
      expect(response.totalTokens, 76);
      expect(response.requestId, 'req-gem-42');
      expect(response.providerCode, 'gemini');
      expect(response.finishReason, 'STOP');

      // Verify call was made against the model-scoped endpoint with the
      // x-goog-api-key header and a payload carrying the source texts.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/models/gemini-3-flash-preview:generateContent');

      final payload = captured[1] as Map<String, dynamic>;
      final contents = payload['contents'] as List;
      expect(contents, isNotEmpty);
      final userMessage = contents.last as Map<String, dynamic>;
      expect(userMessage['role'], 'user');
      final userParts = userMessage['parts'] as List;
      final userText = userParts.first['text'] as String;
      expect(userText, contains('Hello world'));
      expect(userText, contains('Welcome back'));
      expect(userText, contains('fr'));

      final generationConfig = payload['generationConfig'] as Map;
      expect(generationConfig['temperature'], 0.2);
      expect(generationConfig['maxOutputTokens'], 512);
      expect(generationConfig['responseMimeType'], 'application/json');

      // System prompt travels on the systemInstruction branch (not inline
      // with user contents) for Gemini.
      final systemInstruction =
          payload['systemInstruction'] as Map<String, dynamic>;
      final systemParts = systemInstruction['parts'] as List;
      expect(
        systemParts.first['text'] as String,
        contains('Translate videogame UI strings.'),
      );

      final options = captured[2] as Options;
      expect(options.headers,
          containsPair('x-goog-api-key', 'gem-test-key'));
    });

    test('maps 429 response to LlmRateLimitException and propagates '
        'retry-after header as retryAfterSeconds', () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(
          path: '/models/gemini-3-flash-preview:generateContent');
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
            'retry-after': ['11'],
          }),
          data: {
            'error': {
              'code': 429,
              'message': 'Resource has been exhausted',
              'status': 'RESOURCE_EXHAUSTED',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isErr, isTrue);
      final error = result.error;
      expect(error, isA<LlmRateLimitException>());
      final rateLimit = error as LlmRateLimitException;
      expect(rateLimit.retryAfterSeconds, 11);
      expect(rateLimit.providerCode, 'gemini');
    });

    test('maps 403 response to LlmAuthenticationException and does NOT retry '
        '(dio.post called exactly once). Gemini uses 403 (not 401) for bad '
        'API keys.', () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(
          path: '/models/gemini-3-flash-preview:generateContent');
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
          data: {
            'error': {
              'code': 403,
              'message': 'API key not valid. Please pass a valid API key.',
              'status': 'PERMISSION_DENIED',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'gem-bad-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.providerCode, 'gemini');
      // Key invariant: the provider itself does not retry auth failures.
      verify(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).called(1);
    });

    test('maps malformed response (missing candidates) to '
        'LlmResponseParseException instead of throwing', () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // 200 OK but body has no `candidates` field. The provider should
      // wrap this in a parse exception rather than bubbling a type error
      // out to the caller.
      final malformedBody = <String, dynamic>{
        'usageMetadata': {
          'promptTokenCount': 1,
          'candidatesTokenCount': 0,
          'totalTokenCount': 1,
        },
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(malformedBody));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'gemini');
    });

    test('maps finishReason SAFETY to LlmContentFilteredException carrying '
        'source texts and the finishReason. This is the Gemini-signature '
        'moderation branch.', () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest(texts: const {
        'violent_line': 'sensitive source content',
      });

      // Gemini signals safety-blocked content with finishReason=SAFETY.
      // content/parts are typically absent or empty in this case.
      final safetyBody = <String, dynamic>{
        'candidates': [
          {
            'finishReason': 'SAFETY',
            'safetyRatings': [
              {
                'category': 'HARM_CATEGORY_VIOLENCE',
                'probability': 'HIGH',
                'blocked': true,
              },
            ],
          },
        ],
        'usageMetadata': {
          'promptTokenCount': 8,
          'candidatesTokenCount': 0,
          'totalTokenCount': 8,
        },
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(safetyBody));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmContentFilteredException>());
      final filtered = result.error as LlmContentFilteredException;
      expect(filtered.finishReason, 'SAFETY');
      expect(filtered.providerCode, 'gemini');
      expect(filtered.filteredTexts, contains('sensitive source content'));
    });

    test('maps 500 server error to LlmServerException with statusCode '
        'preserved', () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(
          path: '/models/gemini-3-flash-preview:generateContent');
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
          data: {
            'error': {
              'code': 503,
              'message': 'The model is overloaded. Please try again later.',
              'status': 'UNAVAILABLE',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
      final server = result.error as LlmServerException;
      expect(server.statusCode, 503);
      expect(server.providerCode, 'gemini');
    });

    test('maps 400 INVALID_ARGUMENT with token-related message to '
        'LlmTokenLimitException. Gemini-specific routing of 400 status '
        'errors through the errorStatus field.', () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(
          path: '/models/gemini-3-flash-preview:generateContent');
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
          data: {
            'error': {
              'code': 400,
              'message':
                  'The input token count exceeds the maximum number of tokens allowed.',
              'status': 'INVALID_ARGUMENT',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmTokenLimitException>());
      expect(result.error.providerCode, 'gemini');
    });

    test('maps connection timeout DioException to LlmNetworkException',
        () async {
      final dio = _MockDio();
      final provider = GeminiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(
          path: '/models/gemini-3-flash-preview:generateContent');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timed out',
      ));

      final result = await provider.translate(request, 'gem-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.providerCode, 'gemini');
    });
  });
}
