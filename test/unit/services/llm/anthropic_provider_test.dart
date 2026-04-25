import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/anthropic_provider.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/fakes/fake_token_calculator.dart';

// Characterisation tests for AnthropicProvider. Covers request shaping for
// /v1/messages, successful response parsing (text content block + usage),
// and Dio error mapping. Rate-limit retry scheduling is owned by
// LlmRetryHandler (one layer up) and out of scope.

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({Map<String, String>? texts}) {
  return LlmRequest(
    requestId: 'req-99',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: 'claude-3-5-sonnet-20241022',
    maxTokens: 512,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _successResponse(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions: RequestOptions(path: '/messages'),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/messages'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('AnthropicProvider.translate', () {
    test('parses a successful /messages response and forwards request '
        'details (URL, x-api-key header, payload texts)', () async {
      final dio = _MockDio();
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest();

      // Realistic Anthropic response: content is a list of blocks; the first
      // text block carries a JSON-encoded {sourceKey: translatedText} map,
      // exercising the simple key-value branch of _parseTranslations.
      final textPayload = jsonEncode({
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      final successBody = <String, dynamic>{
        'id': 'msg_01ABC',
        'type': 'message',
        'role': 'assistant',
        'model': 'claude-3-5-sonnet-20241022',
        'content': [
          {'type': 'text', 'text': textPayload},
        ],
        'stop_reason': 'end_turn',
        'usage': {
          'input_tokens': 42,
          'output_tokens': 17,
        },
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(successBody));

      final result = await provider.translate(request, 'sk-ant-test');

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final response = result.value;
      expect(response.translations, {
        'ui_title': 'Bonjour le monde',
        'ui_subtitle': 'Bon retour',
      });
      expect(response.modelName, 'claude-3-5-sonnet-20241022');
      expect(response.inputTokens, 42);
      expect(response.outputTokens, 17);
      expect(response.totalTokens, 59);
      expect(response.requestId, 'req-99');
      expect(response.providerCode, 'anthropic');
      expect(response.finishReason, 'end_turn');

      // Verify request shaping: path, payload content, and x-api-key header.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], '/messages');

      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['model'], 'claude-3-5-sonnet-20241022');
      expect(payload['max_tokens'], 512);
      expect(payload.containsKey('temperature'), isFalse);
      expect(payload['system'], isA<String>());
      expect(payload['system'] as String,
          contains('Translate videogame UI strings.'));
      final messages = payload['messages'] as List;
      expect(messages.length, 1);
      final userMessage = messages.first as Map;
      expect(userMessage['role'], 'user');
      expect(userMessage['content'], contains('Hello world'));
      expect(userMessage['content'], contains('Welcome back'));
      expect(userMessage['content'], contains('fr'));

      final options = captured[2] as Options;
      expect(options.headers, containsPair('x-api-key', 'sk-ant-test'));
    });

    test('successful response parsing - array format '
        '({"translations": [{"key": ..., "translation": ...}]})', () async {
      final dio = _MockDio();
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest();

      // Production prompts instruct the LLM to use the array branch of
      // _parseTranslations. This test pins that code path.
      final textPayload = jsonEncode({
        'translations': [
          {'key': 'ui_title', 'translation': 'Titre Principal'},
          {'key': 'ui_subtitle', 'translation': 'Sous-titre'},
        ],
      });
      final successBody = <String, dynamic>{
        'id': 'msg_02DEF',
        'type': 'message',
        'role': 'assistant',
        'model': 'claude-3-5-sonnet-20241022',
        'content': [
          {'type': 'text', 'text': textPayload},
        ],
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 42, 'output_tokens': 17},
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(successBody));

      final result = await provider.translate(request, 'sk-ant-test');

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
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/messages');
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
            'type': 'error',
            'error': {
              'type': 'rate_limit_error',
              'message': 'Rate limit exceeded',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-ant-test');

      expect(result.isErr, isTrue);
      final error = result.error;
      expect(error, isA<LlmRateLimitException>());
      final rateLimit = error as LlmRateLimitException;
      expect(rateLimit.retryAfterSeconds, 11);
      expect(rateLimit.providerCode, 'anthropic');
    });

    test('maps 401 response to LlmAuthenticationException and does NOT retry '
        '(dio.post called exactly once)', () async {
      final dio = _MockDio();
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest();

      final requestOptions = RequestOptions(path: '/messages');
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
            'type': 'error',
            'error': {
              'type': 'authentication_error',
              'message': 'invalid x-api-key',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-ant-bad');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.providerCode, 'anthropic');
      // Key invariant: the provider itself does not retry auth failures.
      verify(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).called(1);
    });

    test('maps malformed response (missing content) to '
        'LlmResponseParseException instead of throwing', () async {
      final dio = _MockDio();
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest();

      // 200 OK but body is missing the required `content` field. The provider
      // should wrap this in a parse exception rather than letting a
      // TypeError/cast failure bubble up to the caller.
      final malformedBody = <String, dynamic>{
        'id': 'msg_broken',
        'model': 'claude-3-5-sonnet-20241022',
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 1, 'output_tokens': 0},
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(malformedBody));

      final result = await provider.translate(request, 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'anthropic');
    });

    test('maps empty text content to LlmContentFilteredException carrying '
        'source texts', () async {
      final dio = _MockDio();
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest(texts: const {'k1': 'sensitive source'});

      // Anthropic signals moderation via empty text content or a
      // 'content_filter' stop_reason. Exercising the empty-text branch here:
      // content list is non-empty but the text block contains an empty string.
      final filteredBody = <String, dynamic>{
        'id': 'msg_filtered',
        'type': 'message',
        'role': 'assistant',
        'model': 'claude-3-5-sonnet-20241022',
        'content': [
          {'type': 'text', 'text': ''},
        ],
        'stop_reason': 'end_turn',
        'usage': {'input_tokens': 5, 'output_tokens': 0},
      };

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _successResponse(filteredBody));

      final result = await provider.translate(request, 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmContentFilteredException>());
      final filtered = result.error as LlmContentFilteredException;
      expect(filtered.filteredTexts, contains('sensitive source'));
      expect(filtered.providerCode, 'anthropic');
    });

    test('maps 529 overloaded_error to LlmServerException with statusCode '
        'preserved (Anthropic-specific overload branch)', () async {
      final dio = _MockDio();
      final provider = AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );
      final request = _buildRequest();

      // Anthropic returns 529 with error.type == "overloaded_error" when the
      // service is temporarily unavailable. This must surface as
      // LlmServerException (>=500 branch of _handleDioException) with the
      // status code preserved so the retry handler upstream can decide.
      final requestOptions = RequestOptions(path: '/messages');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 529,
          requestOptions: requestOptions,
          data: {
            'type': 'error',
            'error': {
              'type': 'overloaded_error',
              'message': 'Overloaded',
            },
          },
        ),
      ));

      final result = await provider.translate(request, 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
      final server = result.error as LlmServerException;
      expect(server.statusCode, 529);
      expect(server.providerCode, 'anthropic');
    });
  });
}
