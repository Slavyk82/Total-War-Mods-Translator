import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/anthropic_provider.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/fakes/fake_token_calculator.dart';

// Complementary coverage for AnthropicProvider. The sibling
// `anthropic_provider_test.dart` already pins the happy path, the array
// response format, missing/partial usage, 429/401/cancel/529 error mapping,
// the missing-content parse failure, the empty-text content-filter branch,
// and a multibyte streaming success. This file adds the remaining UNCOVERED
// branches:
//   - translate() Dio error mapping: timeout, connectionError, generic
//     network, 500 server, 402 + insufficient_quota quota, 400 invalid +
//     400 token-limit, other 4xx, and a non-Dio "unexpected" error.
//   - translate() response-parsing edges: non-text content block,
//     translations-not-a-list, malformed JSON text block.
//   - validateApiKey(): missing model, success, invalid key (401), other Dio
//     failure, non-Dio failure.
//   - estimateTokens / estimateRequestTokens direct calls.
//   - isAvailable(): success + failure.
//   - getRateLimitStatus(): always Ok(null) (Anthropic exposes no headers).
//   - calculateRetryDelay(): retry-after present + default branch.
//   - translateStreaming(): in-stream `error` event + top-level DioException
//     guard.

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({Map<String, String>? texts, String? modelName}) {
  return LlmRequest(
    requestId: 'req-more',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: modelName ?? 'claude-3-5-sonnet-20241022',
    maxTokens: 512,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _okResponse(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions: RequestOptions(path: '/messages'),
  );
}

/// Stub `dio.post(...)` (translate / validateApiKey path) to throw [exception].
void _stubPostThrow(_MockDio dio, Object exception) {
  when(() => dio.post(
        any(),
        data: any(named: 'data'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
      )).thenThrow(exception);
}

/// Stub `dio.post(...)` to answer with [response].
void _stubPostAnswer(_MockDio dio, Response<dynamic> response) {
  when(() => dio.post(
        any(),
        data: any(named: 'data'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => response);
}

DioException _badResponse({
  required int statusCode,
  Map<String, dynamic>? data,
  Headers? headers,
}) {
  final requestOptions = RequestOptions(path: '/messages');
  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      statusCode: statusCode,
      requestOptions: requestOptions,
      data: data,
      headers: headers ?? Headers(),
    ),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/messages'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  AnthropicProvider buildProvider(_MockDio dio) => AnthropicProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
        logger: FakeLogger(),
      );

  group('AnthropicProvider.translate — Dio error mapping', () {
    test('connectionTimeout maps to LlmNetworkException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          type: DioExceptionType.connectionTimeout,
          message: 'connect timed out',
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.providerCode, 'anthropic');
      expect(result.error.message, contains('timeout'));
    });

    test('receiveTimeout maps to LlmNetworkException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          type: DioExceptionType.receiveTimeout,
          message: 'receive timed out',
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
    });

    test('connectionError maps to LlmNetworkException with "Connection failed"',
        () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          type: DioExceptionType.connectionError,
          message: 'host unreachable',
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Connection failed'));
    });

    test('unknown DioException type (no status) falls through to default '
        'network error', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          type: DioExceptionType.unknown,
          message: 'something odd',
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Network error'));
    });

    test('500 maps to LlmServerException preserving statusCode', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 500,
          data: {
            'type': 'error',
            'error': {'type': 'api_error', 'message': 'Internal error'},
          },
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      final server = result.error as LlmServerException;
      expect(server.statusCode, 500);
      expect(server.providerCode, 'anthropic');
    });

    test('402 maps to LlmQuotaException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 402,
          data: {
            'type': 'error',
            'error': {'type': 'billing_error', 'message': 'Payment required'},
          },
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmQuotaException>());
      expect(result.error.providerCode, 'anthropic');
    });

    test('insufficient_quota error type maps to LlmQuotaException even with '
        'a 400 status', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 400,
          data: {
            'type': 'error',
            'error': {
              'type': 'insufficient_quota',
              'message': 'You exceeded your quota',
            },
          },
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmQuotaException>());
    });

    test('400 invalid_request_error mentioning "token" maps to '
        'LlmTokenLimitException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 400,
          data: {
            'type': 'error',
            'error': {
              'type': 'invalid_request_error',
              'message': 'prompt is too long: 250000 tokens > max',
            },
          },
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmTokenLimitException>());
      expect(result.error.providerCode, 'anthropic');
    });

    test('400 invalid_request_error without "token" maps to '
        'LlmInvalidRequestException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 400,
          data: {
            'type': 'error',
            'error': {
              'type': 'invalid_request_error',
              'message': 'messages: field required',
            },
          },
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error, isNot(isA<LlmTokenLimitException>()));
    });

    test('other 4xx (404) maps to LlmInvalidRequestException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 404,
          data: {
            'type': 'error',
            'error': {'type': 'not_found_error', 'message': 'not found'},
          },
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
    });

    test('non-Map error response body is stringified into the message',
        () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      final requestOptions = RequestOptions(path: '/messages');
      _stubPostThrow(
        dio,
        DioException(
          requestOptions: requestOptions,
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            statusCode: 503,
            requestOptions: requestOptions,
            data: 'plain text gateway error',
          ),
        ),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      final server = result.error as LlmServerException;
      expect(server.statusCode, 503);
      expect(server.message, contains('plain text gateway error'));
    });

    test('a non-Dio thrown error maps to a generic LlmProviderException with '
        'code UNEXPECTED_ERROR', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      // ArgumentError is not a DioException nor an LlmProviderException, so it
      // hits the catch-all in translate().
      _stubPostThrow(dio, ArgumentError('boom'));

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'UNEXPECTED_ERROR');
      expect(result.error.message, contains('Unexpected error'));
    });
  });

  group('AnthropicProvider.translate — response parsing edges', () {
    test('non-text content block only -> empty text -> content filtered',
        () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      // content has a non-text block; firstWhere(orElse) yields {'text': ''},
      // which (non-empty content + empty text) trips the content-filter branch.
      _stubPostAnswer(
        dio,
        _okResponse({
          'id': 'msg_tooluse',
          'model': 'claude-3-5-sonnet-20241022',
          'content': [
            {'type': 'tool_use', 'name': 'x', 'input': {}},
          ],
          'stop_reason': 'tool_use',
          'usage': {'input_tokens': 3, 'output_tokens': 1},
        }),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmContentFilteredException>());
    });

    test('text block with malformed JSON maps to LlmResponseParseException',
        () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      _stubPostAnswer(
        dio,
        _okResponse({
          'id': 'msg_badjson',
          'model': 'claude-3-5-sonnet-20241022',
          'content': [
            {'type': 'text', 'text': 'this is not json at all, sorry'},
          ],
          'stop_reason': 'end_turn',
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        }),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'anthropic');
    });

    test('"translations" present but not a List maps to '
        'LlmResponseParseException', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      final textPayload = jsonEncode({'translations': 'oops-not-a-list'});
      _stubPostAnswer(
        dio,
        _okResponse({
          'id': 'msg_badarr',
          'model': 'claude-3-5-sonnet-20241022',
          'content': [
            {'type': 'text', 'text': textPayload},
          ],
          'stop_reason': 'end_turn',
          'usage': {'input_tokens': 5, 'output_tokens': 2},
        }),
      );

      final result = await provider.translate(_buildRequest(), 'sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });
  });

  group('AnthropicProvider.validateApiKey', () {
    test('returns LlmInvalidRequestException when model is null', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      final result = await provider.validateApiKey('sk-ant-test');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, contains('Model is required'));
      // No network call should have been made.
      verifyNever(() => dio.post(any(),
          data: any(named: 'data'), options: any(named: 'options')));
    });

    test('returns Ok(true) on 200 response', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response<dynamic>(
            statusCode: 200,
            data: {'id': 'msg', 'content': []},
            requestOptions: RequestOptions(path: '/messages'),
          ));

      final result =
          await provider.validateApiKey('sk-ant-test', model: 'claude-x');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('maps 401 to LlmAuthenticationException ("Invalid API key")',
        () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      final requestOptions = RequestOptions(path: '/messages');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 401,
          requestOptions: requestOptions,
          data: {
            'type': 'error',
            'error': {'type': 'authentication_error', 'message': 'bad key'},
          },
        ),
      ));

      final result =
          await provider.validateApiKey('sk-ant-bad', model: 'claude-x');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.message, contains('Invalid API key'));
    });

    test('non-401 Dio failure flows through _handleDioException (429 -> '
        'rate limit)', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      final requestOptions = RequestOptions(path: '/messages');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 429,
          requestOptions: requestOptions,
          data: {
            'type': 'error',
            'error': {'type': 'rate_limit_error', 'message': 'slow down'},
          },
        ),
      ));

      final result =
          await provider.validateApiKey('sk-ant-test', model: 'claude-x');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmRateLimitException>());
    });

    test('non-Dio failure maps to generic LlmProviderException with '
        'VALIDATION_ERROR code', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(StateError('unexpected'));

      final result =
          await provider.validateApiKey('sk-ant-test', model: 'claude-x');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'VALIDATION_ERROR');
    });
  });

  group('AnthropicProvider — token estimation', () {
    test('estimateTokens delegates to the token calculator', () {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      // FakeTokenCalculator.calculateAnthropicTokens == text.length ~/ 4.
      final tokens = provider.estimateTokens('abcdefgh'); // 8 chars
      expect(tokens, isA<int>());
      expect(tokens, 2);
    });

    test('estimateRequestTokens delegates to the token calculator', () {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      final tokens = provider.estimateRequestTokens(_buildRequest());
      expect(tokens, isA<int>());
      expect(tokens, greaterThan(0));
    });
  });

  group('AnthropicProvider.isAvailable', () {
    test('returns Ok(true) when GET / responds with status < 500', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/'),
        ),
      );

      final result = await provider.isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('returns Err(LlmNetworkException) when the GET throws', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      when(() => dio.get(any(), options: any(named: 'options'))).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionError,
        ),
      );

      final result = await provider.isAvailable();

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.providerCode, 'anthropic');
    });
  });

  group('AnthropicProvider.getRateLimitStatus', () {
    test('always returns Ok(null) — Anthropic exposes no rate-limit headers',
        () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      final result = await provider.getRateLimitStatus('sk-ant-test');

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });
  });

  group('AnthropicProvider.calculateRetryDelay', () {
    test('uses retryAfterSeconds when present', () {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException(
          'rate limited',
          providerCode: 'anthropic',
          retryAfterSeconds: 7,
        ),
      );

      expect(delay, const Duration(seconds: 7));
    });

    test('falls back to a 60s default when retryAfterSeconds is null', () {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException(
          'rate limited',
          providerCode: 'anthropic',
        ),
      );

      expect(delay, const Duration(seconds: 60));
    });
  });

  group('AnthropicProvider.translateStreaming — error paths', () {
    test('emits Err for an in-stream `error` event then stops', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);

      final sse = 'data: ${jsonEncode({
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          })}\n\n';
      final byteStream =
          Stream<Uint8List>.fromIterable([Uint8List.fromList(utf8.encode(sse))]);
      final responseBody = ResponseBody(byteStream, 200);

      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response<dynamic>(
            data: responseBody,
            statusCode: 200,
            requestOptions: RequestOptions(path: '/messages'),
          ));

      final results =
          await provider.translateStreaming(_buildRequest(), 'sk-ant').toList();

      final errors = results.where((r) => r.isErr).toList();
      expect(errors, hasLength(1));
      expect(errors.first.error, isA<LlmProviderException>());
      expect(errors.first.error.code, 'STREAMING_ERROR');
      expect(errors.first.error.message, contains('Overloaded'));
    });

    test('top-level DioException is mapped via _handleDioException (429 -> '
        'rate limit)', () async {
      final dio = _MockDio();
      final provider = buildProvider(dio);
      final requestOptions = RequestOptions(path: '/messages');
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: requestOptions,
        type: DioExceptionType.badResponse,
        response: Response<dynamic>(
          statusCode: 429,
          requestOptions: requestOptions,
          data: {
            'type': 'error',
            'error': {'type': 'rate_limit_error', 'message': 'slow down'},
          },
        ),
      ));

      final results =
          await provider.translateStreaming(_buildRequest(), 'sk-ant').toList();

      expect(results, hasLength(1));
      expect(results.first.isErr, isTrue);
      expect(results.first.error, isA<LlmRateLimitException>());
    });
  });
}
