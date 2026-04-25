import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/deepseek_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Characterisation tests for DeepSeekProvider. DeepSeek uses an
// OpenAI-compatible API (/chat/completions, Bearer auth, choices[0].message
// .content), so these tests mirror openai_provider_test.dart while pinning
// DeepSeek-specific payload quirks (max_tokens vs max_completion_tokens,
// default model deepseek-v4-flash) and the wider error-mapping branches
// (insufficient_quota -> LlmQuotaException, context_length_exceeded ->
// LlmTokenLimitException). Retry scheduling is owned by LlmRetryHandler and
// is out of scope here.

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
    modelName: 'deepseek-v4-flash',
    maxTokens: 4096,
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

  group('DeepSeekProvider.translate', () {
    test('parses a successful /chat/completions response and forwards request '
        'details (URL, Authorization header, body texts, max_tokens)',
        () async {
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // Simple key-value branch of _parseTranslations (not the array branch).
      final content = jsonEncode({
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      final successBody = <String, dynamic>{
        'id': 'chatcmpl-abc123',
        'object': 'chat.completion',
        'model': 'deepseek-v4-flash',
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
      expect(response.modelName, 'deepseek-v4-flash');
      expect(response.inputTokens, 42);
      expect(response.outputTokens, 17);
      expect(response.totalTokens, 59);
      expect(response.requestId, 'req-42');
      expect(response.providerCode, 'deepseek');
      expect(response.finishReason, 'stop');

      // Verify call was made against /chat/completions with the correct
      // Authorization header and a DeepSeek-shaped payload carrying the
      // source texts.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/chat/completions');

      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['model'], 'deepseek-v4-flash');
      expect(payload['response_format'], {'type': 'json_object'});
      // DeepSeek uses max_tokens (not max_completion_tokens like OpenAI).
      expect(payload['max_tokens'], 4096);
      expect(payload.containsKey('max_completion_tokens'), isFalse);
      expect(payload.containsKey('temperature'), isFalse);
      final messages = payload['messages'] as List;
      expect(messages.length, greaterThanOrEqualTo(2));
      final userMessage = messages.last as Map;
      expect(userMessage['role'], 'user');
      expect(userMessage['content'], contains('Hello world'));
      expect(userMessage['content'], contains('Welcome back'));
      expect(userMessage['content'], contains('fr'));

      final options = captured[2] as Options;
      expect(
          options.headers, containsPair('Authorization', 'Bearer sk-test-key'));
    });

    test('successful response parsing - array format '
        '({"translations": [{"key": ..., "translation": ...}]})', () async {
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // Production prompts (PromptBuilderService) instruct the LLM to use the
      // array branch of _parseTranslations. This test pins that code path.
      final content = jsonEncode({
        'translations': [
          {'key': 'ui_title', 'translation': 'Titre Principal'},
          {'key': 'ui_subtitle', 'translation': 'Sous-titre'},
        ],
      });
      final successBody = <String, dynamic>{
        'id': 'chatcmpl-test',
        'object': 'chat.completion',
        'model': 'deepseek-v4-flash',
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
        'ui_title': 'Titre Principal',
        'ui_subtitle': 'Sous-titre',
      });
      expect(response.inputTokens, 42);
      expect(response.outputTokens, 17);
    });

    test('maps 429 response to LlmRateLimitException and propagates '
        'retry-after header as retryAfterSeconds', () async {
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
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
      expect(rateLimit.providerCode, 'deepseek');
    });

    test('maps 401 response to LlmAuthenticationException and does NOT retry '
        '(dio.post called exactly once)', () async {
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
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
              'message': 'Authentication Fails, Your api key is invalid',
              'type': 'authentication_error',
              'code': 'invalid_api_key',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-bad');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.providerCode, 'deepseek');
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
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
      final request = _buildRequest();

      // 200 OK but body is missing the required `choices` field. The
      // provider should wrap this in a parse exception rather than letting
      // a TypeError/cast failure bubble up to the caller.
      final malformedBody = <String, dynamic>{
        'id': 'chatcmpl-broken',
        'model': 'deepseek-v4-flash',
        'usage': {
          'prompt_tokens': 1,
          'completion_tokens': 0,
          'total_tokens': 1,
        },
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
      expect(result.error.providerCode, 'deepseek');
    });

    test('maps 500 server error to LlmServerException with statusCode '
        'preserved', () async {
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
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
      expect(server.providerCode, 'deepseek');
    });

    test('maps 402 / insufficient_quota to LlmQuotaException (DeepSeek '
        'distinct branch: billing failure is separate from rate limit)',
        () async {
      // DeepSeek returns 402 Payment Required (or an `insufficient_quota`
      // error code) when the account balance is exhausted. This is a
      // dedicated branch in _handleDioException that OpenAI covers too but
      // the test file for OpenAI did not exercise -- worth pinning here
      // because the failure mode is user-visible and must not be confused
      // with a rate limit.
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
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
          statusCode: 402,
          requestOptions: requestOptions,
          data: {
            'error': {
              'message': 'Insufficient balance',
              'type': 'insufficient_quota',
              'code': 'insufficient_quota',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmQuotaException>());
      expect(result.error.providerCode, 'deepseek');
    });

    test('maps 400 context_length_exceeded to LlmTokenLimitException '
        '(DeepSeek distinct branch vs generic 400 invalid request)',
        () async {
      // _handleDioException has a dedicated branch that promotes a 400 whose
      // error type/code is invalid_request_error / context_length_exceeded
      // AND whose message mentions "token" or "context length" into a
      // typed LlmTokenLimitException. Without this branch the caller would
      // get a generic LlmInvalidRequestException and lose the hint.
      final dio = _MockDio();
      final provider = DeepSeekProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );
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
          statusCode: 400,
          requestOptions: requestOptions,
          data: {
            'error': {
              'message':
                  "This model's maximum context length is 65536 tokens. "
                      'Requested 70000 tokens.',
              'type': 'invalid_request_error',
              'code': 'context_length_exceeded',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-test-key');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmTokenLimitException>());
      expect(result.error.providerCode, 'deepseek');
    });
  });
}
