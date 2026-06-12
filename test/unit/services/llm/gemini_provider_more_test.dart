import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/gemini_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

// Complementary characterisation tests for GeminiProvider. These cover the
// branches NOT exercised by gemini_provider_test.dart: validateApiKey,
// isAvailable, getRateLimitStatus, calculateRetryDelay, the token-estimation
// pass-throughs, the remaining _parseResponse / _parseTranslations edges, and
// the _handleDioException paths (401, generic 400/4xx, connectionError, the
// unknown-type fallback, and non-Map error bodies).

class _MockDio extends Mock implements Dio {}

const _endpoint = '/models/gemini-3-flash-preview:generateContent';

LlmRequest _buildRequest({Map<String, String>? texts}) {
  return LlmRequest(
    requestId: 'req-gem-more',
    targetLanguage: 'fr',
    texts: texts ??
        const {
          'ui_title': 'Hello world',
          'ui_subtitle': 'Welcome back',
        },
    systemPrompt: 'Translate videogame UI strings.',
    modelName: 'gemini-3-flash-preview',
    maxTokens: 512,
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

Response<dynamic> _ok(Map<String, dynamic> body, {int statusCode = 200}) {
  return Response<dynamic>(
    data: body,
    statusCode: statusCode,
    requestOptions: RequestOptions(path: _endpoint),
  );
}

/// Build a Gemini :generateContent success body whose candidate text is
/// [innerText] (the JSON-encoded translations payload the provider re-decodes).
Map<String, dynamic> _candidateBody(
  String innerText, {
  String finishReason = 'STOP',
  Map<String, dynamic>? usageMetadata = const {
    'promptTokenCount': 10,
    'candidatesTokenCount': 5,
    'totalTokenCount': 15,
  },
}) {
  return <String, dynamic>{
    'candidates': [
      {
        'content': {
          'role': 'model',
          'parts': [
            {'text': innerText}
          ],
        },
        'finishReason': finishReason,
      },
    ],
    if (usageMetadata != null) 'usageMetadata': usageMetadata,
  };
}

DioException _dioErr({
  int? statusCode,
  Object? data,
  Headers? headers,
  DioExceptionType type = DioExceptionType.badResponse,
  String? message,
}) {
  final requestOptions = RequestOptions(path: _endpoint);
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

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: _endpoint));
    registerFallbackValue(Options());
    registerFallbackValue(CancelToken());
  });

  GeminiProvider build(_MockDio dio) =>
      GeminiProvider(dio: dio, tokenCalculator: FakeTokenCalculator());

  void stubPost(_MockDio dio, Object answerOrThrow, {bool throws = false}) {
    final when0 = when(() => dio.post(
          any(),
          data: any(named: 'data'),
          cancelToken: any(named: 'cancelToken'),
          options: any(named: 'options'),
        ));
    if (throws) {
      when0.thenThrow(answerOrThrow);
    } else {
      when0.thenAnswer((_) async => answerOrThrow as Response);
    }
  }

  // ---------------------------------------------------------------------------
  // translate: response-parsing edges
  // ---------------------------------------------------------------------------
  group('GeminiProvider.translate parse edges', () {
    test('empty candidates list -> LlmResponseParseException', () async {
      final dio = _MockDio();
      stubPost(dio, _ok(<String, dynamic>{'candidates': <dynamic>[]}));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
      expect(result.error.providerCode, 'gemini');
    });

    test('candidate without content field -> LlmResponseParseException',
        () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _ok(<String, dynamic>{
          'candidates': [
            {'finishReason': 'STOP'}
          ],
        }),
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('content with empty parts -> LlmResponseParseException', () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _ok(<String, dynamic>{
          'candidates': [
            {
              'content': {'role': 'model', 'parts': <dynamic>[]},
              'finishReason': 'STOP',
            }
          ],
        }),
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('blank text in part -> LlmResponseParseException', () async {
      final dio = _MockDio();
      stubPost(dio, _ok(_candidateBody('   ')));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('non-JSON candidate text -> LlmResponseParseException', () async {
      final dio = _MockDio();
      stubPost(dio, _ok(_candidateBody('this is not json at all')));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('JSON array (not object) candidate text -> LlmResponseParseException',
        () async {
      final dio = _MockDio();
      stubPost(dio, _ok(_candidateBody('[1, 2, 3]')));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test(
        'translations-array shape (key/translation objects) is parsed into the '
        'translations map', () async {
      final dio = _MockDio();
      final inner = jsonEncode({
        'translations': [
          {'key': 'ui_title', 'translation': 'Bonjour'},
          {'key': 'ui_subtitle', 'translation': 'Bon retour'},
          // non-map item is skipped
          'garbage',
          // item missing translation is skipped
          {'key': 'ui_extra'},
        ],
      });
      stubPost(dio, _ok(_candidateBody(inner)));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue, reason: '$result');
      expect(result.value.translations, {
        'ui_title': 'Bonjour',
        'ui_subtitle': 'Bon retour',
      });
    });

    test('translations field present but not a List -> ParseException',
        () async {
      final dio = _MockDio();
      final inner = jsonEncode({'translations': 'oops-a-string'});
      stubPost(dio, _ok(_candidateBody(inner)));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('markdown-fenced JSON in candidate text is unwrapped', () async {
      final dio = _MockDio();
      final inner = '```json\n${jsonEncode({'ui_title': 'Salut'})}\n```';
      stubPost(dio, _ok(_candidateBody(inner)));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue, reason: '$result');
      expect(result.value.translations, {'ui_title': 'Salut'});
    });

    test(
        'empty-string values are dropped; all-empty against non-empty request '
        '-> ParseException', () async {
      final dio = _MockDio();
      final inner = jsonEncode({'ui_title': '', 'ui_subtitle': '   '});
      stubPost(dio, _ok(_candidateBody(inner)));

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmResponseParseException>());
    });

    test('missing usageMetadata defaults token counts to zero', () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _ok(_candidateBody(jsonEncode({'ui_title': 'Salut'}),
            usageMetadata: null)),
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isOk, isTrue, reason: '$result');
      expect(result.value.inputTokens, 0);
      expect(result.value.outputTokens, 0);
      expect(result.value.totalTokens, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // translate: remaining _handleDioException branches
  // ---------------------------------------------------------------------------
  group('GeminiProvider.translate Dio error mapping (extra)', () {
    test('401 -> LlmAuthenticationException', () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _dioErr(statusCode: 401, data: {
          'error': {'message': 'Unauthorized', 'status': 'UNAUTHENTICATED'}
        }),
        throws: true,
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
    });

    test('400 INVALID_ARGUMENT without token wording -> '
        'LlmInvalidRequestException', () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _dioErr(statusCode: 400, data: {
          'error': {
            'message': 'Request contains an invalid field.',
            'status': 'INVALID_ARGUMENT',
          }
        }),
        throws: true,
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
      expect(result.error, isNot(isA<LlmTokenLimitException>()));
    });

    test('generic 404 (4xx, non-special status) -> LlmInvalidRequestException',
        () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _dioErr(statusCode: 404, data: {
          'error': {'message': 'Model not found', 'status': 'NOT_FOUND'}
        }),
        throws: true,
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmInvalidRequestException>());
    });

    test('connectionError -> LlmNetworkException', () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _dioErr(type: DioExceptionType.connectionError, message: 'no route'),
        throws: true,
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
    });

    test('unknown DioExceptionType with no response -> LlmNetworkException '
        '(fallback)', () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _dioErr(type: DioExceptionType.unknown, message: 'boom'),
        throws: true,
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
    });

    test('error body that is a String (not a Map) is still mapped, not thrown',
        () async {
      final dio = _MockDio();
      stubPost(
        dio,
        _dioErr(statusCode: 503, data: 'plain text gateway error'),
        throws: true,
      );

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
      expect((result.error as LlmServerException).statusCode, 503);
    });

    test('non-DioException thrown from dio.post -> LlmProviderException '
        'UNEXPECTED_ERROR', () async {
      final dio = _MockDio();
      stubPost(dio, StateError('kaboom'), throws: true);

      final result = await build(dio).translate(_buildRequest(), 'k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'UNEXPECTED_ERROR');
    });
  });

  // ---------------------------------------------------------------------------
  // validateApiKey
  // ---------------------------------------------------------------------------
  group('GeminiProvider.validateApiKey', () {
    test('200 -> Ok(true) and posts a minimal payload with x-goog-api-key',
        () async {
      final dio = _MockDio();
      stubPost(dio, _ok(<String, dynamic>{'candidates': <dynamic>[]}));

      final result = await build(dio).validateApiKey('good-key');

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);

      final captured = verify(() => dio.post(
            captureAny(),
            data: captureAny(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: captureAny(named: 'options'),
          )).captured;
      expect(captured[0], _endpoint);
      final payload = captured[1] as Map<String, dynamic>;
      expect(payload['contents'], isA<List>());
      expect((payload['generationConfig'] as Map)['maxOutputTokens'], 10);
      final options = captured[2] as Options;
      expect(options.headers, containsPair('x-goog-api-key', 'good-key'));
    });

    test('honours an explicit model override in the endpoint path', () async {
      final dio = _MockDio();
      stubPost(dio, _ok(<String, dynamic>{'candidates': <dynamic>[]}));

      await build(dio).validateApiKey('k', model: 'gemini-3-pro-preview');

      final captured = verify(() => dio.post(
            captureAny(),
            data: any(named: 'data'),
            cancelToken: any(named: 'cancelToken'),
            options: any(named: 'options'),
          )).captured;
      expect(captured[0], '/models/gemini-3-pro-preview:generateContent');
    });

    test('401 -> LlmAuthentication("Invalid API key")', () async {
      final dio = _MockDio();
      stubPost(dio, _dioErr(statusCode: 401), throws: true);

      final result = await build(dio).validateApiKey('bad');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      expect(result.error.message, 'Invalid API key');
    });

    test('403 -> LlmAuthenticationException', () async {
      final dio = _MockDio();
      stubPost(dio, _dioErr(statusCode: 403), throws: true);

      final result = await build(dio).validateApiKey('bad');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
    });

    test('non-auth Dio error (500) routes through _handleDioException', () async {
      final dio = _MockDio();
      stubPost(dio, _dioErr(statusCode: 500), throws: true);

      final result = await build(dio).validateApiKey('k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmServerException>());
    });

    test('non-Dio error -> LlmProviderException VALIDATION_ERROR', () async {
      final dio = _MockDio();
      stubPost(dio, StateError('weird'), throws: true);

      final result = await build(dio).validateApiKey('k');

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmProviderException>());
      expect(result.error.code, 'VALIDATION_ERROR');
    });
  });

  // ---------------------------------------------------------------------------
  // isAvailable
  // ---------------------------------------------------------------------------
  group('GeminiProvider.isAvailable', () {
    test('200 from GET /models -> Ok(true)', () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 200,
          requestOptions: RequestOptions(path: '/models'),
        ),
      );

      final result = await build(dio).isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isTrue);
    });

    test('non-200 (e.g. 404) -> Ok(false)', () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options'))).thenAnswer(
        (_) async => Response<dynamic>(
          statusCode: 404,
          requestOptions: RequestOptions(path: '/models'),
        ),
      );

      final result = await build(dio).isAvailable();

      expect(result.isOk, isTrue);
      expect(result.value, isFalse);
    });

    test('thrown error -> Err(LlmNetworkException "Service unavailable")',
        () async {
      final dio = _MockDio();
      when(() => dio.get(any(), options: any(named: 'options')))
          .thenThrow(_dioErr(type: DioExceptionType.connectionError));

      final result = await build(dio).isAvailable();

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmNetworkException>());
      expect(result.error.message, 'Service unavailable');
    });
  });

  // ---------------------------------------------------------------------------
  // getRateLimitStatus / calculateRetryDelay / token estimation / flags
  // ---------------------------------------------------------------------------
  group('GeminiProvider misc', () {
    test('getRateLimitStatus -> Ok(null) (Gemini does not expose it)',
        () async {
      final result = await build(_MockDio()).getRateLimitStatus('k');
      expect(result.isOk, isTrue);
      expect(result.value, isNull);
    });

    test('calculateRetryDelay uses retryAfterSeconds when present', () {
      final provider = build(_MockDio());
      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException('rate limited',
            providerCode: 'gemini', retryAfterSeconds: 7),
      );
      expect(delay, const Duration(seconds: 7));
    });

    test('calculateRetryDelay defaults to 60s when no retryAfterSeconds', () {
      final provider = build(_MockDio());
      final delay = provider.calculateRetryDelay(
        const LlmRateLimitException('rate limited', providerCode: 'gemini'),
      );
      expect(delay, const Duration(seconds: 60));
    });

    test('estimateTokens delegates to the token calculator', () {
      // FakeTokenCalculator returns text.length ~/ 4.
      expect(build(_MockDio()).estimateTokens('abcdefgh'), 2);
    });

    test('estimateRequestTokens delegates to the token calculator', () {
      final provider = build(_MockDio());
      final request = _buildRequest(texts: const {'a': '12345678'});
      // (systemPrompt.length + 8) ~/ 4
      final expected =
          (request.systemPrompt.length + '12345678'.length) ~/ 4;
      expect(provider.estimateRequestTokens(request), expected);
    });

    test('exposes provider identity and supportsStreaming', () {
      final provider = build(_MockDio());
      expect(provider.providerCode, 'gemini');
      expect(provider.providerName, 'Google Gemini');
      expect(provider.supportsStreaming, isTrue);
      expect(provider.config.providerCode, 'gemini');
    });
  });
}
