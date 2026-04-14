import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/openai_provider.dart';

// Characterisation tests for OpenAiProvider. Covers request shaping,
// successful response parsing, and Dio error mapping. Rate-limit retry
// scheduling is owned by LlmRetryHandler (one layer up) and out of scope.

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({Map<String, String>? texts}) {
  return LlmRequest(
    requestId: 'req-42',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: 'gpt-4o-mini',
    maxTokens: 512,
    temperature: 0.2,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _successResponse(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions: RequestOptions(path: '/chat/completions'),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/chat/completions'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('OpenAiProvider.translate', () {
    test('parses a successful /chat/completions response and forwards request '
        'details (URL, Authorization header, body texts)', () async {
      final dio = _MockDio();
      final provider = OpenAiProvider(dio: dio);
      final request = _buildRequest();

      // Realistic OpenAI chat-completion body. content holds a JSON-encoded
      // {sourceKey: translatedText} map, which exercises the simple
      // key-value branch of _parseTranslations (not the {"translations": [...]}
      // array branch).
      final content = jsonEncode({
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      final successBody = <String, dynamic>{
        'id': 'chatcmpl-abc123',
        'object': 'chat.completion',
        'model': 'gpt-4o-mini',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': content},
            'finish_reason': 'stop',
          },
        ],
        'usage': {
          'prompt_tokens': 42,
          'completion_tokens': 17,
          'total_tokens': 59,
        },
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(successBody));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final response = result.value;
      expect(response.translations, {
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      expect(response.modelName, 'gpt-4o-mini');
      expect(response.inputTokens, 42);
      expect(response.outputTokens, 17);
      expect(response.totalTokens, 59);
      expect(response.requestId, 'req-42');
      expect(response.providerCode, 'openai');
      expect(response.finishReason, 'stop');

      // Verify call was made against /chat/completions with the correct
      // Authorization header and a payload carrying the source texts.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/chat/completions');

      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['model'], 'gpt-4o-mini');
      expect(payload['response_format'], {'type': 'json_object'});
      expect(payload['max_completion_tokens'], 512);
      expect(payload['temperature'], 0.2);
      final messages = payload['messages'] as List;
      // System + user messages at minimum.
      expect(messages.length, greaterThanOrEqualTo(2));
      final userMessage = messages.last as Map;
      expect(userMessage['role'], 'user');
      expect(userMessage['content'], contains('Hello world'));
      expect(userMessage['content'], contains('Welcome back'));
      expect(userMessage['content'], contains('fr'));

      final options = captured[2] as Options;
      expect(options.headers, containsPair('Authorization', 'Bearer sk-test-key'));
    });

    test('maps 429 response to LlmRateLimitException and propagates '
        'retry-after header as retryAfterSeconds', () async {
      final dio = _MockDio();
      final provider = OpenAiProvider(dio: dio);
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/chat/completions');
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
            'retry-after': ['7'],
            'x-ratelimit-remaining-requests': ['0'],
            'x-ratelimit-remaining-tokens': ['0'],
          }),
          data: {
            'error': {
              'message': 'Rate limit exceeded',
              'type': 'rate_limit_exceeded',
              'code': 'rate_limit_exceeded',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isErr, isTrue);
      final error = result.error;
      expect(error, isA<LlmRateLimitException>());
      final rateLimit = error as LlmRateLimitException;
      expect(rateLimit.retryAfterSeconds, 7);
      expect(rateLimit.providerCode, 'openai');
      expect(rateLimit.rateLimitRpm, 0);
      expect(rateLimit.rateLimitTpm, 0);
    });

    test('maps 401 response to LlmAuthenticationException and does NOT retry '
        '(dio.post called exactly once)', () async {
      final dio = _MockDio();
      final provider = OpenAiProvider(dio: dio);
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/chat/completions');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 401,
          requestOptions: requestOptions,
          data: {
            'error': {
              'message': 'Incorrect API key provided',
              'type': 'invalid_request_error',
              'code': 'invalid_api_key',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-bad');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.providerCode, 'openai');
      // Key invariant: the provider itself does not retry auth failures.
      verify(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).called(1);
    });

    test('maps malformed response (missing choices) to '
        'LlmResponseParseException instead of throwing', () async {
      final dio = _MockDio();
      final provider = OpenAiProvider(dio: dio);
      final request = _buildRequest();

      // 200 OK but body is missing the required `choices` field. The
      // provider should wrap this in a parse exception rather than letting
      // a TypeError/cast failure bubble up to the caller.
      final malformedBody = <String, dynamic>{
        'id': 'chatcmpl-broken',
        'model': 'gpt-4o-mini',
        'usage': {'prompt_tokens': 1, 'completion_tokens': 0, 'total_tokens': 1},
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(malformedBody));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'openai');
    });

    test('maps empty content (content filter) to '
        'LlmContentFilteredException carrying source texts', () async {
      final dio = _MockDio();
      final provider = OpenAiProvider(dio: dio);
      final request = _buildRequest(texts: const {'k1': 'sensitive source'});

      // OpenAI sometimes signals moderation either via finish_reason or by
      // returning empty content. Exercising the finish_reason branch here.
      final filteredBody = <String, dynamic>{
        'id': 'chatcmpl-filtered',
        'model': 'gpt-4o-mini',
        'choices': [
          {
            'index': 0,
            'message': {'role': 'assistant', 'content': ''},
            'finish_reason': 'content_filter',
          },
        ],
        'usage': {'prompt_tokens': 5, 'completion_tokens': 0, 'total_tokens': 5},
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(filteredBody));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmContentFilteredException>());
      final filtered = result.error as LlmContentFilteredException;
      expect(filtered.finishReason, 'content_filter');
      expect(filtered.filteredTexts, contains('sensitive source'));
    });

    test('maps 500 server error to LlmServerException with statusCode '
        'preserved', () async {
      final dio = _MockDio();
      final provider = OpenAiProvider(dio: dio);
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/chat/completions');
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
              'message': 'Upstream overloaded',
              'type': 'server_error',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
      final server = result.error as LlmServerException;
      expect(server.statusCode, 503);
      expect(server.providerCode, 'openai');
    });
  });
}
