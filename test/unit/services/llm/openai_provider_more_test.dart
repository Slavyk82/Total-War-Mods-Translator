import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/openai_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Complementary characterisation tests for OpenAiProvider.
//
// The sibling file `openai_provider_test.dart` already covers the happy-path
// translate(), the 429 / 401 / cancel / 500 mappings, the missing-choices and
// content-filter parse branches, the 'length' truncation regression, and a
// multibyte streaming-reassembly case. This file ADDS the still-uncovered
// branches and methods:
//   * _handleDioException: timeout (connect/receive/send), connectionError,
//     quota (402 + insufficient_quota type/code), token-limit (400 +
//     context_length_exceeded), max_tokens-not-supported, generic 400,
//     other 4xx, non-Map / null error bodies, default network fall-through.
//   * translate(): non-Dio unexpected error -> UNEXPECTED_ERROR; ArgumentError
//     from a missing modelName surfaces as UNEXPECTED_ERROR.
//   * _parseResponse / _parseTranslations: missing usage, markdown-wrapped
//     JSON, empty-string translations filtered as missing, all-empty -> parse
//     error, non-object JSON, malformed JSON content.
//   * _buildRequestPayload few-shot example branch.
//   * validateApiKey: model-required guard, success, 401, other Dio error,
//     non-Dio failure.
//   * estimateTokens / estimateRequestTokens (delegation to TokenCalculator).
//   * isAvailable: success + failure.
//   * getRateLimitStatus: always Ok(null) sentinel.
//   * calculateRetryDelay: retry-after-present vs default 60s.

class _MockDio extends Mock implements Dio {}

LlmRequest _buildRequest({
  Map<String, String>? texts,
  String? modelName = 'gpt-4o-mini',
  List<TranslationExample>? fewShotExamples,
}) {
  return LlmRequest(
    requestId: 'req-99',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: modelName,
    maxTokens: 512,
    fewShotExamples: fewShotExamples,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _okResponse(Map<String, dynamic> body) {
  return Response<dynamic>(
    data: body,
    statusCode: 200,
    requestOptions: RequestOptions(path: '/chat/completions'),
  );
}

Map<String, dynamic> _completionBody({
  required String content,
  String model = 'gpt-4o-mini',
  Map<String, dynamic>? usage,
  String finishReason = 'stop',
}) {
  return <String, dynamic>{
    'id': 'chatcmpl-x',
    'object': 'chat.completion',
    'model': model,
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

DioException _badResponse({
  required int statusCode,
  Object? data,
  Headers? headers,
}) {
  final requestOptions = RequestOptions(path: '/chat/completions');
  return DioException(
    requestOptions: requestOptions,
    type: DioExceptionType.badResponse,
    response: Response<dynamic>(
      statusCode: statusCode,
      requestOptions: requestOptions,
      data: data,
      headers: headers,
    ),
  );
}

DioException _typed(DioExceptionType type, {String? message}) {
  return DioException(
    requestOptions: RequestOptions(path: '/chat/completions'),
    type: type,
    message: message,
  );
}

void _stubPostThrow(_MockDio dio, Object error) {
  when(() => dio.post(
        any(),
        data: any(named: 'data'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
      )).thenThrow(error);
}

void _stubPostAnswer(_MockDio dio, Response<dynamic> response) {
  when(() => dio.post(
        any(),
        data: any(named: 'data'),
        cancelToken: any(named: 'cancelToken'),
        options: any(named: 'options'),
      )).thenAnswer((_) async => response);
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: '/chat/completions'));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  OpenAiProvider buildProvider(_MockDio dio) => OpenAiProvider(
        dio: dio,
        tokenCalculator: FakeTokenCalculator(),
      );

  group('OpenAiProvider.translate - _handleDioException timeout/network', () {
    test('connectionTimeout maps to LlmNetworkException (request timeout)',
        () async {
      final dio = _MockDio();
      _stubPostThrow(
          dio, _typed(DioExceptionType.connectionTimeout, message: 'too slow'));

      final result = await buildProvider(dio).translate(
        _buildRequest(),
        'sk-test',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('timeout'));
      expect(result.error.providerCode, 'openai');
    });

    test('receiveTimeout maps to LlmNetworkException', () async {
      final dio = _MockDio();
      _stubPostThrow(dio, _typed(DioExceptionType.receiveTimeout));

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('timeout'));
    });

    test('sendTimeout maps to LlmNetworkException', () async {
      final dio = _MockDio();
      _stubPostThrow(dio, _typed(DioExceptionType.sendTimeout));

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmNetworkException>());
    });

    test('connectionError maps to LlmNetworkException (connection failed)',
        () async {
      final dio = _MockDio();
      _stubPostThrow(dio,
          _typed(DioExceptionType.connectionError, message: 'host down'));

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Connection failed'));
    });

    test('unknown DioException with no response falls through to default '
        'LlmNetworkException', () async {
      final dio = _MockDio();
      _stubPostThrow(
          dio, _typed(DioExceptionType.unknown, message: 'mystery'));

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, contains('Network error'));
      expect(result.error.message, contains('mystery'));
    });
  });

  group('OpenAiProvider.translate - _handleDioException status codes', () {
    test('402 maps to LlmQuotaException', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 402, data: {
          'error': {'message': 'Billing hard limit reached'},
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmQuotaException>());
      expect(result.error.message, contains('Billing hard limit'));
    });

    test('429 with insufficient_quota type maps to LlmQuotaException, not '
        'rate limit (quota check is evaluated even on 429 when type set... '
        'but here uses 403 to isolate quota-by-type)', () async {
      // Rate-limit (429) is checked before quota, so to exercise the
      // quota-by-error-type branch we use a non-429/402 status with the
      // insufficient_quota type.
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 403, data: {
          'error': {
            'message': 'You exceeded your current quota',
            'type': 'insufficient_quota',
          },
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmQuotaException>());
    });

    test('insufficient_quota by error code (not type) maps to '
        'LlmQuotaException', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 403, data: {
          'error': {
            'message': 'quota gone',
            'code': 'insufficient_quota',
          },
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmQuotaException>());
    });

    test('400 context_length_exceeded with "token" in message maps to '
        'LlmTokenLimitException', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 400, data: {
          'error': {
            'message': 'This model maximum context length is 8192 tokens',
            'code': 'context_length_exceeded',
          },
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmTokenLimitException>());
      expect(result.error.message, contains('context length'));
    });

    test('400 invalid_request_error mentioning "context length" maps to '
        'LlmTokenLimitException', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 400, data: {
          'error': {
            'message': 'Requested context length exceeds the limit',
            'type': 'invalid_request_error',
          },
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmTokenLimitException>());
    });

    test('400 "max_tokens ... not supported" maps to LlmTokenLimitException '
        '(the message contains "token", so token-limit detection wins)', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 400, data: {
          'error': {
            'message':
                "Unsupported parameter: 'max_tokens' is not supported with this model.",
            'type': 'invalid_request_error',
          },
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmTokenLimitException>());
      expect(result.error.message, contains('max_tokens'));
    });

    test('generic 400 (no token/quota signal) maps to '
        'LlmInvalidRequestException echoing the API message', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 400, data: {
          'error': {
            'message': 'Invalid value for response_format',
            'type': 'invalid_request_error',
          },
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, 'Invalid value for response_format');
    });

    test('non-400 4xx (e.g. 404) maps to LlmInvalidRequestException', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 404, data: {
          'error': {'message': 'model not found'},
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, 'model not found');
    });

    test('5xx server error preserves status code on LlmServerException',
        () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 500, data: {
          'error': {'message': 'internal'},
        }),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmServerException>());
      expect((result.error as LlmServerException).statusCode, 500);
    });

    test('error body that is a non-Map (plain string) is surfaced as the '
        'error message', () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(statusCode: 400, data: 'Bad Request raw text'),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, 'Bad Request raw text');
    });

    test('error response with null body falls back to "Unknown error"',
        () async {
      final dio = _MockDio();
      _stubPostThrow(dio, _badResponse(statusCode: 400, data: null));

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error.message, 'Unknown error');
    });

    test('429 without retry-after header leaves retryAfterSeconds null',
        () async {
      final dio = _MockDio();
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 429,
          data: {
            'error': {'message': 'slow down'},
          },
          headers: Headers.fromMap(const {}),
        ),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      final err = result.error as LlmRateLimitException;
      expect(err.retryAfterSeconds, isNull);
      expect(err.rateLimitRpm, isNull);
      expect(err.rateLimitTpm, isNull);
    });

    test('429 with non-numeric retry-after but parseable reset timestamp '
        'derives retryAfterSeconds from reset time', () async {
      final dio = _MockDio();
      final reset = DateTime.now().add(const Duration(seconds: 30));
      _stubPostThrow(
        dio,
        _badResponse(
          statusCode: 429,
          data: {
            'error': {'message': 'rate limited'},
          },
          headers: Headers.fromMap({
            'retry-after': const ['not-a-number'],
            'x-ratelimit-reset-requests': [reset.toIso8601String()],
          }),
        ),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      final err = result.error as LlmRateLimitException;
      // Derived from reset - now; allow a generous window for clock drift.
      expect(err.retryAfterSeconds, isNotNull);
      expect(err.retryAfterSeconds, inInclusiveRange(0, 31));
    });
  });

  group('OpenAiProvider.translate - non-Dio errors and payload guards', () {
    test('missing modelName throws ArgumentError inside payload build, '
        'surfaced as UNEXPECTED_ERROR LlmProviderException', () async {
      final dio = _MockDio();
      // dio.post is never reached because _buildRequestPayload throws first;
      // no stub needed, but provide a benign one to be safe.
      _stubPostAnswer(dio, _okResponse(_completionBody(content: '{}')));

      final result = await buildProvider(dio).translate(
        _buildRequest(modelName: null),
        'k',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'UNEXPECTED_ERROR');
    });

    test('non-Dio exception thrown by Dio surfaces as UNEXPECTED_ERROR',
        () async {
      final dio = _MockDio();
      _stubPostThrow(dio, StateError('boom'));

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'UNEXPECTED_ERROR');
      expect(result.error.message, contains('boom'));
    });

    test('few-shot examples are injected as user/assistant message pairs in '
        'the payload', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode({'ui_title': 'X', 'ui_subtitle': 'Y'}),
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final request = _buildRequest(fewShotExamples: const [
        TranslationExample(source: 'Attack', target: 'Attaque'),
      ]);

      final result = await buildProvider(dio).translate(request, 'k');
      expect(result.isOk, isTrue);

      final captured = verify(() => dio.post(
            any(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).captured;
      final payload = captured.single as Map<String, dynamic>;
      final messages = payload['messages'] as List;
      // system + user(example) + assistant(example) + user(request) = 4
      expect(messages.length, 4);
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], contains('Attack'));
      expect(messages[2]['role'], 'assistant');
      expect(messages[2]['content'], contains('Attaque'));
    });
  });

  group('OpenAiProvider.translate - response/translation parse edges', () {
    test('missing usage block defaults token counts to 0', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode({'ui_title': 'A', 'ui_subtitle': 'B'}),
          // no usage key
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue);
      expect(result.value.inputTokens, 0);
      expect(result.value.outputTokens, 0);
      expect(result.value.totalTokens, 0);
    });

    test('markdown-fenced JSON content is unwrapped before parsing', () async {
      final dio = _MockDio();
      final fenced = '```json\n'
          '${jsonEncode({'ui_title': 'Titre', 'ui_subtitle': 'Sous'})}\n'
          '```';
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: fenced,
          usage: const {'prompt_tokens': 3, 'completion_tokens': 4},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue);
      expect(result.value.translations, {
        'ui_title': 'Titre',
        'ui_subtitle': 'Sous',
      });
    });

    test('empty-string translation values are dropped as missing but a '
        'non-empty sibling still yields a partial Ok', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode({'ui_title': 'Titre', 'ui_subtitle': '   '}),
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue);
      expect(result.value.translations.containsKey('ui_title'), isTrue);
      expect(result.value.translations.containsKey('ui_subtitle'), isFalse);
    });

    test('all translations empty -> LlmResponseParseException (no valid '
        'translations found)', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode({'ui_title': '', 'ui_subtitle': ''}),
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('content that is valid JSON but not an object (a JSON array) -> '
        'LlmResponseParseException', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode(['a', 'b']),
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('malformed JSON content -> LlmResponseParseException', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: '{not valid json',
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('"translations" array branch with a non-array value -> '
        'LlmResponseParseException', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode({'translations': 'oops-not-an-array'}),
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('"translations" array branch skips malformed items but keeps valid '
        'ones', () async {
      final dio = _MockDio();
      _stubPostAnswer(
        dio,
        _okResponse(_completionBody(
          content: jsonEncode({
            'translations': [
              'not-a-map',
              {'key': 'ui_title', 'translation': 'Titre'},
              {'key': 'ui_subtitle'}, // missing translation -> skipped
            ],
          }),
          usage: const {'prompt_tokens': 1, 'completion_tokens': 1},
        )),
      );

      final result = await buildProvider(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue);
      expect(result.value.translations, {'ui_title': 'Titre'});
    });
  });

  group('OpenAiProvider.validateApiKey', () {
    test('returns LlmInvalidRequestException when model is null', () async {
      final dio = _MockDio();
      final result = await buildProvider(dio).validateApiKey('sk-x');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      verifyNever(() => dio.post(any(),
          data: any(named: 'data'), options: any(named: 'options')));
    });

    test('returns Ok(true) on a 200 validation response', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => _okResponse(const {'ok': true}));

      final result =
          await buildProvider(dio).validateApiKey('sk-x', model: 'gpt-4o-mini');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);

      // The validation payload uses max_completion_tokens, not max_tokens.
      final captured = verify(() => dio.post(
            any(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;
      final payload = captured.single as Map<String, dynamic>;
      expect(payload['max_completion_tokens'], 10);
      expect(payload['model'], 'gpt-4o-mini');
    });

    test('maps 401 to LlmAuthenticationException', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_badResponse(statusCode: 401, data: {
        'error': {'message': 'bad key'},
      }));

      final result =
          await buildProvider(dio).validateApiKey('sk-bad', model: 'gpt-4o');

      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.message, 'Invalid API key');
    });

    test('non-401 Dio error is delegated to _handleDioException (e.g. 500 -> '
        'LlmServerException)', () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_badResponse(statusCode: 500, data: {
        'error': {'message': 'down'},
      }));

      final result =
          await buildProvider(dio).validateApiKey('sk-x', model: 'gpt-4o');

      expect(result.error, isA<LlmServerException>());
    });

    test('non-Dio failure -> LlmProviderException with VALIDATION_ERROR code',
        () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(StateError('weird'));

      final result =
          await buildProvider(dio).validateApiKey('sk-x', model: 'gpt-4o');

      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'VALIDATION_ERROR');
    });
  });

  group('OpenAiProvider.estimateTokens / estimateRequestTokens', () {
    test('estimateTokens delegates to TokenCalculator (length ~/ 4)', () {
      final provider = buildProvider(_MockDio());
      // FakeTokenCalculator returns text.length ~/ 4.
      expect(provider.estimateTokens('12345678'), 2);
    });

    test('estimateRequestTokens delegates to TokenCalculator', () {
      final provider = buildProvider(_MockDio());
      final request = _buildRequest(texts: const {'k': 'abcdabcd'});
      // (systemPrompt.length + 8) ~/ 4 per the fake.
      final expected =
          ('Translate videogame UI strings.'.length + 8) ~/ 4;
      expect(provider.estimateRequestTokens(request), expected);
    });
  });

  group('OpenAiProvider.isAvailable', () {
    test('returns Ok(true) when /models responds 200', () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/models'),
        ),
      );

      final result = await buildProvider(dio).isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('returns Ok(false) when /models responds non-200 (e.g. 401)',
        () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 401,
          requestOptions: RequestOptions(path: '/models'),
        ),
      );

      final result = await buildProvider(dio).isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });

    test('returns Err(LlmNetworkException) when the health check throws',
        () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenThrow(_typed(DioExceptionType.connectionError));

      final result = await buildProvider(dio).isAvailable();

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, 'Service unavailable');
    });
  });

  group('OpenAiProvider.getRateLimitStatus', () {
    test('returns Ok(null) sentinel (status tracked from response headers '
        'elsewhere)', () async {
      final result = await buildProvider(_MockDio()).getRateLimitStatus('sk-x');

      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });
  });

  group('OpenAiProvider.calculateRetryDelay', () {
    test('uses retryAfterSeconds from the exception when present', () {
      final provider = buildProvider(_MockDio());
      const ex = LlmRateLimitException(
        'rate limited',
        providerCode: 'openai',
        retryAfterSeconds: 12,
      );

      expect(provider.calculateRetryDelay(ex), const Duration(seconds: 12));
    });

    test('falls back to a 60s default when retryAfterSeconds is null', () {
      final provider = buildProvider(_MockDio());
      const ex = LlmRateLimitException('rate limited', providerCode: 'openai');

      expect(provider.calculateRetryDelay(ex), const Duration(seconds: 60));
    });
  });

  group('OpenAiProvider.translateStreaming error branch', () {
    test('a DioException thrown while opening the stream is mapped through '
        '_handleDioException and yielded as a single Err', () async {
      final dio = _MockDio();
      // Streaming uses dio.post WITHOUT a cancelToken arg, so match the
      // 3-arg overload (any, data, options).
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(_badResponse(statusCode: 401, data: {
        'error': {'message': 'bad key'},
      }));

      final results = await buildProvider(dio)
          .translateStreaming(_buildRequest(), 'sk-bad')
          .toList();

      expect(results, hasLength(1));
      expect(results.single.isErr, isTrue);
      expect(results.single.error, isA<LlmAuthenticationException>());
    });

    test('a non-Dio error while opening the stream yields STREAMING_ERROR',
        () async {
      final dio = _MockDio();
      when(() => dio.post(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(StateError('stream boom'));

      final results = await buildProvider(dio)
          .translateStreaming(_buildRequest(), 'sk-x')
          .toList();

      expect(results, hasLength(1));
      expect(results.single.isErr, isTrue);
      expect(results.single.error.code, 'STREAMING_ERROR');
    });
  });
}
