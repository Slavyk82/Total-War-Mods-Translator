import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/deepseek_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Complementary coverage for DeepSeekProvider. The sibling file
// deepseek_provider_test.dart pins the happy paths and a handful of headline
// error mappings (429 / 401 / cancel / 500 / quota / token-limit / two parse
// edges). This file ADDS the remaining uncovered branches WITHOUT duplicating
// those cases:
//   * translate(): unexpected (non-Dio) error wrapping, missing usage default,
//     malformed translation JSON, content_filter via non-empty path, and the
//     400-invalid-request / generic-4xx / connection-error / timeout /
//     unknown-network branches of _handleDioException.
//   * validateApiKey(): success, 401 -> auth, other Dio error, non-Dio error.
//   * estimateTokens / estimateRequestTokens (delegation to TokenCalculator).
//   * isAvailable(): 200 ok, non-200 ok=false, thrown -> LlmNetworkException.
//   * getRateLimitStatus(): always Ok(null).
//   * calculateRetryDelay(): retry-after honoured vs default 60s fallback.
//   * translateStreaming(): multi-delta accumulation, [DONE] terminator,
//     finish_reason terminator, malformed-chunk skip, and DioException ->
//     Err mapping.
// DeepSeek is OpenAI-compatible (/chat/completions, Bearer auth,
// choices[0].message.content, usage.{prompt,completion}_tokens).

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({Map<String, String>? texts}) {
  return LlmRequest(
    requestId: 'req-more',
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

Response<dynamic> _ok(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions: RequestOptions(path: '/chat/completions'),
  );
}

Map<String, dynamic> _completion(String content,
    {String finishReason = 'stop', Map<String, dynamic>? usage}) {
  return <String, dynamic>{
    'id': 'chatcmpl-x',
    'object': 'chat.completion',
    'model': 'deepseek-v4-flash',
    'choices': [
      {
        'index': 0,
        'message': {'role': 'assistant', 'content': content},
        'finish_reason': finishReason,
      },
    ],
    if (usage != null) 'usage': usage,
  };
}

DioException _dioError(int? statusCode,
    {Map<String, dynamic>? data,
    Headers? headers,
    DioExceptionType type = DioExceptionType.badResponse,
    String? message}) {
  final requestOptions = RequestOptions(path: '/chat/completions');
  return DioException(
    requestOptions: requestOptions,
    type: type,
    message: message,
    response: statusCode == null
        ? null
        : Response<dynamic>(
            statusCode: statusCode,
            requestOptions: requestOptions,
            headers: headers,
            data: data,
          ),
  );
}

void _stubPost(_MockDio dio, Object answerOrThrow) {
  final stub = when(() => dio.post(
        any(),
        data: any(named: 'data'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
      ));
  if (answerOrThrow is Response<dynamic>) {
    stub.thenAnswer((_) async => answerOrThrow);
  } else {
    stub.thenThrow(answerOrThrow);
  }
}

DeepSeekProvider _provider(_MockDio dio) =>
    DeepSeekProvider(dio: dio, tokenCalculator: FakeTokenCalculator());

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/chat/completions'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  group('DeepSeekProvider.translate - extra branches', () {
    test('wraps a non-Dio, non-Llm error thrown during the call in a generic '
        'LlmProviderException with code UNEXPECTED_ERROR', () async {
      final dio = _MockDio();
      _stubPost(dio, StateError('socket exploded'));

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      final err = result.error;
      expect(err, isA<LlmProviderException>());
      expect(err, isNot(isA<LlmNetworkException>()));
      expect(err.code, 'UNEXPECTED_ERROR');
      expect(err.providerCode, 'deepseek');
      expect(err.message, contains('socket exploded'));
    });

    test('defaults input/output tokens to 0 when the usage object is absent '
        'from the response body', () async {
      final dio = _MockDio();
      final content = jsonEncode({
        'ui_title': 'Bonjour',
        'ui_subtitle': 'Salut',
      });
      // No `usage` key at all -> null-safe defaults exercised.
      _stubPost(dio, _ok(_completion(content)));

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isOk, isTrue, reason: '$result');
      final resp = result.value;
      expect(resp.inputTokens, 0);
      expect(resp.outputTokens, 0);
      expect(resp.totalTokens, 0);
      expect(resp.translations, {'ui_title': 'Bonjour', 'ui_subtitle': 'Salut'});
    });

    test('maps content that is valid JSON but not a JSON object to '
        'LlmResponseParseException (translations parse failure)', () async {
      final dio = _MockDio();
      // A JSON array, not an object: _parseTranslations throws FormatException
      // which is wrapped into LlmResponseParseException.
      _stubPost(dio, _ok(_completion('[1, 2, 3]')));

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'deepseek');
    });

    test('maps content with NO valid translations (all empty values) to '
        'LlmResponseParseException', () async {
      final dio = _MockDio();
      final content = jsonEncode({'ui_title': '   ', 'ui_subtitle': ''});
      _stubPost(dio, _ok(_completion(content)));

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('strips a ```json markdown fence around the JSON object before '
        'parsing translations', () async {
      final dio = _MockDio();
      final inner = jsonEncode({'ui_title': 'Titre', 'ui_subtitle': 'Sous'});
      final content = '```json\n$inner\n```';
      _stubPost(
        dio,
        _ok(_completion(content,
            usage: {'prompt_tokens': 3, 'completion_tokens': 2})),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isOk, isTrue, reason: '$result');
      expect(result.value.translations,
          {'ui_title': 'Titre', 'ui_subtitle': 'Sous'});
    });

    test('non-empty content with finish_reason "content_filter" is still '
        'classified as LlmContentFilteredException', () async {
      // Companion to the empty-content filter test in the sibling file: here
      // content is non-empty but finishReason explicitly flags filtering.
      final dio = _MockDio();
      final content = jsonEncode({'ui_title': 'whatever'});
      _stubPost(
        dio,
        _ok(_completion(content, finishReason: 'content_filter')),
      );

      final result = await _provider(dio)
          .translate(_buildRequest(texts: const {'ui_title': 'src'}), 'sk');

      expect(result.isErr, isTrue);
      final err = result.error;
      expect(err, isA<LlmContentFilteredException>());
      expect((err as LlmContentFilteredException).finishReason,
          'content_filter');
    });

    test('maps a generic 400 (no token/context hint) to '
        'LlmInvalidRequestException, not LlmTokenLimitException', () async {
      final dio = _MockDio();
      _stubPost(
        dio,
        _dioError(400, data: {
          'error': {
            'message': 'Missing required parameter: messages',
            'type': 'invalid_request_error',
            'code': 'missing_parameter',
          },
        }),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error, isNot(isA<LlmTokenLimitException>()));
    });

    test('maps a non-400/401/429 4xx (e.g. 404) to '
        'LlmInvalidRequestException', () async {
      final dio = _MockDio();
      _stubPost(
        dio,
        _dioError(404, data: {
          'error': {'message': 'Not found'}
        }),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, contains('Not found'));
    });

    test('maps a receiveTimeout (no response) to LlmNetworkException with a '
        'timeout message', () async {
      final dio = _MockDio();
      _stubPost(
        dio,
        _dioError(null,
            type: DioExceptionType.receiveTimeout, message: 'took too long'),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('timeout'));
    });

    test('maps a connectionError (no response) to LlmNetworkException with a '
        'connection-failed message', () async {
      final dio = _MockDio();
      _stubPost(
        dio,
        _dioError(null,
            type: DioExceptionType.connectionError, message: 'refused'),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Connection failed'));
    });

    test('maps an unknown DioException (no response, no recognised type) to a '
        'default LlmNetworkException', () async {
      final dio = _MockDio();
      _stubPost(
        dio,
        _dioError(null, type: DioExceptionType.unknown, message: 'mystery'),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Network error'));
    });

    test('429 with NO retry-after header yields null retryAfterSeconds', () async {
      final dio = _MockDio();
      _stubPost(
        dio,
        _dioError(429, data: {
          'error': {'message': 'slow down'}
        }),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      final err = result.error;
      expect(err, isA<LlmRateLimitException>());
      expect((err as LlmRateLimitException).retryAfterSeconds, isNull);
    });

    test('error response with a non-Map body falls back to its string form '
        'in the error message', () async {
      final dio = _MockDio();
      // responseData is a plain string -> the else branch stringifies it.
      _stubPost(
        dio,
        DioException(
          requestOptions: RequestOptions(path: '/chat/completions'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            statusCode: 503,
            requestOptions: RequestOptions(path: '/chat/completions'),
            data: 'Service Unavailable plain text',
          ),
        ),
      );

      final result = await _provider(dio).translate(_buildRequest(), 'sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
      expect(result.error.message, contains('Service Unavailable plain text'));
    });
  });

  group('DeepSeekProvider.validateApiKey', () {
    test('returns Ok(true) when the validation request returns 200', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok(<String, dynamic>{'ok': true}));

      final result = await _provider(dio).validateApiKey('sk-valid');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);

      // Pins the minimal validation payload shape.
      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;
      expect(captured[0], '/chat/completions');
      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['model'], 'deepseek-v4-flash');
      expect(payload['max_tokens'], 10);
    });

    test('honours an explicit model override in the validation payload',
        () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _ok(<String, dynamic>{'ok': true}));

      await _provider(dio).validateApiKey('sk', model: 'deepseek-v4-pro');

      final captured = verify(() => dio.post(
            any(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;
      expect((captured[0] as Map)['model'], 'deepseek-v4-pro');
    });

    test('maps a 401 during validation to LlmAuthenticationException', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_dioError(401, data: {
        'error': {'message': 'bad key'}
      }));

      final result = await _provider(dio).validateApiKey('sk-bad');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.message, contains('Invalid API key'));
    });

    test('maps a non-401 Dio error during validation through '
        '_handleDioException (e.g. 500 -> LlmServerException)', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_dioError(500, data: {
        'error': {'message': 'boom'}
      }));

      final result = await _provider(dio).validateApiKey('sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
    });

    test('wraps a non-Dio error during validation in a generic '
        'LlmProviderException with code VALIDATION_ERROR', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(StateError('weird'));

      final result = await _provider(dio).validateApiKey('sk');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'VALIDATION_ERROR');
    });
  });

  group('DeepSeekProvider token estimation', () {
    test('estimateTokens delegates to the TokenCalculator', () {
      final provider = _provider(_MockDio());
      // FakeTokenCalculator returns text.length ~/ 4.
      expect(provider.estimateTokens('abcdefgh'), 2);
    });

    test('estimateRequestTokens delegates to the TokenCalculator', () {
      final provider = _provider(_MockDio());
      final request = _buildRequest(texts: const {'a': 'four'});
      // (systemPrompt.length + 'four'.length) ~/ 4
      final expected =
          (request.systemPrompt.length + 'four'.length) ~/ 4;
      expect(provider.estimateRequestTokens(request), expected);
    });
  });

  group('DeepSeekProvider.isAvailable', () {
    test('returns Ok(true) when GET /models responds 200', () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenAnswer((_) async => Response<dynamic>(
                statusCode: 200,
                requestOptions: RequestOptions(path: '/models'),
              ));

      final result = await _provider(dio).isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('returns Ok(false) when GET /models responds with a non-200 status '
        '(e.g. 404 under validateStatus < 500)', () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenAnswer((_) async => Response<dynamic>(
                statusCode: 404,
                requestOptions: RequestOptions(path: '/models'),
              ));

      final result = await _provider(dio).isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });

    test('returns Err(LlmNetworkException) when the connectivity probe throws',
        () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenThrow(_dioError(null, type: DioExceptionType.connectionError));

      final result = await _provider(dio).isAvailable();

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Service unavailable'));
    });
  });

  group('DeepSeekProvider.getRateLimitStatus', () {
    test('returns Ok(null) - DeepSeek exposes no dedicated rate-limit endpoint',
        () async {
      final result = await _provider(_MockDio()).getRateLimitStatus('sk');
      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });
  });

  group('DeepSeekProvider.calculateRetryDelay', () {
    test('honours retryAfterSeconds from the exception when present', () {
      final provider = _provider(_MockDio());
      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException('rl',
            providerCode: 'deepseek', retryAfterSeconds: 12),
      );
      expect(delay, const Duration(seconds: 12));
    });

    test('falls back to a fixed 60s backoff when retryAfterSeconds is null', () {
      final provider = _provider(_MockDio());
      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException('rl', providerCode: 'deepseek'),
      );
      expect(delay, const Duration(seconds: 60));
    });
  });

  group('DeepSeekProvider.translateStreaming', () {
    Response<dynamic> streamResponse(String sse) {
      final body = ResponseBody(
        Stream<Uint8List>.fromIterable(
            [Uint8List.fromList(utf8.encode(sse))]),
        200,
      );
      return Response<dynamic>(
        data: body,
        statusCode: 200,
        requestOptions: RequestOptions(path: '/chat/completions'),
      );
    }

    void stubStream(_MockDio dio, Object answerOrThrow) {
      final stub = when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          ));
      if (answerOrThrow is DioException) {
        stub.thenThrow(answerOrThrow);
      } else {
        stub.thenAnswer((_) async => answerOrThrow as Response<dynamic>);
      }
    }

    test('accumulates content deltas across multiple SSE events and stops at '
        '[DONE]', () async {
      final dio = _MockDio();
      final sse = 'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'Bon'},
                'finish_reason': null,
              }
            ],
          })}\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'jour'},
                'finish_reason': null,
              }
            ],
          })}\n'
          'data: [DONE]\n';
      stubStream(dio, streamResponse(sse));

      final results =
          await _provider(dio).translateStreaming(_buildRequest(), 'sk').toList();

      expect(results.where((r) => r.isErr), isEmpty);
      final text = results.where((r) => r.isOk).map((r) => r.value).join();
      expect(text, 'Bonjour');
    });

    test('stops yielding once a non-null finish_reason is observed', () async {
      final dio = _MockDio();
      final sse = 'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'first'},
                'finish_reason': null,
              }
            ],
          })}\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'last'},
                'finish_reason': 'stop',
              }
            ],
          })}\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'IGNORED'},
                'finish_reason': null,
              }
            ],
          })}\n';
      stubStream(dio, streamResponse(sse));

      final results =
          await _provider(dio).translateStreaming(_buildRequest(), 'sk').toList();

      final text = results.where((r) => r.isOk).map((r) => r.value).join();
      // 'last' is yielded before the break; the post-finish event is unreachable.
      expect(text, 'firstlast');
      expect(text, isNot(contains('IGNORED')));
    });

    test('skips malformed JSON chunks without erroring the stream', () async {
      final dio = _MockDio();
      final sse = 'data: {not valid json\n'
          'data: ${jsonEncode({
            'choices': [
              {
                'delta': {'content': 'ok'},
                'finish_reason': null,
              }
            ],
          })}\n'
          'data: [DONE]\n';
      stubStream(dio, streamResponse(sse));

      final results =
          await _provider(dio).translateStreaming(_buildRequest(), 'sk').toList();

      expect(results.where((r) => r.isErr), isEmpty);
      expect(results.where((r) => r.isOk).map((r) => r.value).join(), 'ok');
    });

    test('maps a DioException raised while opening the stream to an Err result',
        () async {
      final dio = _MockDio();
      stubStream(
        dio,
        _dioError(429, data: {
          'error': {'message': 'rate limited'}
        }),
      );

      final results =
          await _provider(dio).translateStreaming(_buildRequest(), 'sk').toList();

      expect(results, hasLength(1));
      expect(results.single.isErr, isTrue);
      expect(results.single.error, isA<LlmRateLimitException>());
    });
  });

  group('DeepSeekProvider metadata', () {
    test('exposes provider identity, streaming support and config', () {
      final provider = _provider(_MockDio());
      expect(provider.providerCode, 'deepseek');
      expect(provider.providerName, 'DeepSeek');
      expect(provider.supportsStreaming, isTrue);
      expect(provider.config, isNotNull);
    });
  });
}
