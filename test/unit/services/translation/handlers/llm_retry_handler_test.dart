import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/translation/handlers/llm_retry_handler.dart';

import '../../../../helpers/mock_logging_service.dart';

// Characterisation tests for LlmRetryHandler. Covers:
// - happy path (single call, no retries)
// - rate-limit retry with provider-suggested delay (fakeAsync clock)
// - retry exhaustion after N attempts
// - non-retryable auth error returned immediately (critical invariant)
// - retry on LlmServerException (5xx) exercises the server-error branch
// - warn-log emitted per retry iteration (pins logger contract)

class _MockLlmService extends Mock implements ILlmService {}

LlmRequest _buildRequest() {
  return LlmRequest(
    requestId: 'req-retry-1',
    targetLanguage: 'fr',
    texts: const {'k1': 'Hello'},
    systemPrompt: 'Translate.',
    modelName: 'gpt-4o-mini',
    timestamp: DateTime(2026, 4, 14, 12, 0, 0),
  );
}

LlmResponse _buildResponse() {
  return LlmResponse(
    requestId: 'req-retry-1',
    translations: const {'k1': 'Bonjour'},
    providerCode: 'openai',
    modelName: 'gpt-4o-mini',
    inputTokens: 10,
    outputTokens: 5,
    totalTokens: 15,
    processingTimeMs: 100,
    timestamp: DateTime(2026, 4, 14, 12, 0, 1),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_buildRequest());
    registerFallbackValue(CancelToken());
    registerFallbackValue(StackTrace.empty);
  });

  group('LlmRetryHandler.translateWithRetry', () {
    test('returns Ok immediately when the first call succeeds '
        '(no retry, no warning logged)', () async {
      final llmService = _MockLlmService();
      final logger = MockLoggingService();
      final handler =
          LlmRetryHandler(llmService: llmService, logger: logger);
      final response = _buildResponse();

      when(() => llmService.translateBatch(any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async => Ok(response));

      final result = await handler.translateWithRetry(
        llmRequest: _buildRequest(),
        batchId: 'batch-1',
        dioCancelToken: CancelToken(),
        maxRetries: 3,
      );

      expect(result.isOk, isTrue);
      expect(result.value, same(response));
      verify(() => llmService.translateBatch(any(),
          cancelToken: any(named: 'cancelToken'))).called(1);
      // No retry attempted => no warning logged.
      verifyNever(() => logger.warning(any(), any()));
      verifyNever(() => logger.warning(any()));
    });

    test('retries after LlmRateLimitException with provider-suggested '
        'retryAfterSeconds delay and returns Ok on second call', () {
      fakeAsync((async) {
        final llmService = _MockLlmService();
        final logger = MockLoggingService();
        final handler =
            LlmRetryHandler(llmService: llmService, logger: logger);
        final response = _buildResponse();
        final rateLimit = const LlmRateLimitException(
          'Rate limit exceeded',
          providerCode: 'openai',
          retryAfterSeconds: 5,
        );

        var callCount = 0;
        when(() => llmService.translateBatch(any(),
            cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return Err<LlmResponse, LlmServiceException>(rateLimit);
          }
          return Ok<LlmResponse, LlmServiceException>(response);
        });

        Result<LlmResponse, LlmServiceException>? resolved;
        handler
            .translateWithRetry(
          llmRequest: _buildRequest(),
          batchId: 'batch-rl',
          dioCancelToken: CancelToken(),
          maxRetries: 3,
        )
            .then((r) {
          resolved = r;
        });

        // Drain the first call microtasks.
        async.flushMicrotasks();
        expect(callCount, 1,
            reason: 'first call should have fired before backoff');
        expect(resolved, isNull,
            reason: 'handler must wait retryAfterSeconds before retrying');

        // Advance by less than retryAfterSeconds => still waiting.
        async.elapse(const Duration(seconds: 4));
        expect(callCount, 1);
        expect(resolved, isNull);

        // Crossing the provider-suggested boundary triggers the retry.
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(callCount, 2);
        expect(resolved, isNotNull);
        expect(resolved!.isOk, isTrue);
        expect(resolved!.value, same(response));
      });
    });

    test('returns Err after maxRetries retryable failures; total call count '
        'is maxRetries + 1 (attempts are zero-indexed through <= maxRetries)',
        () {
      fakeAsync((async) {
        final llmService = _MockLlmService();
        final logger = MockLoggingService();
        final handler =
            LlmRetryHandler(llmService: llmService, logger: logger);
        // retryAfterSeconds: 1 keeps the fake clock easy to advance.
        final rateLimit = const LlmRateLimitException(
          'Rate limit exceeded',
          providerCode: 'openai',
          retryAfterSeconds: 1,
        );

        when(() => llmService.translateBatch(any(),
                cancelToken: any(named: 'cancelToken')))
            .thenAnswer((_) async =>
                Err<LlmResponse, LlmServiceException>(rateLimit));

        Result<LlmResponse, LlmServiceException>? resolved;
        handler
            .translateWithRetry(
          llmRequest: _buildRequest(),
          batchId: 'batch-exhaust',
          dioCancelToken: CancelToken(),
          maxRetries: 2,
        )
            .then((r) {
          resolved = r;
        });

        // Advance a generous amount of time to let every backoff elapse.
        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(resolved, isNotNull);
        expect(resolved!.isErr, isTrue);
        expect(resolved!.error, isA<LlmRateLimitException>());
        // Loop runs while attempt <= maxRetries, so maxRetries=2 yields
        // attempts 0, 1, 2 => 3 total calls.
        verify(() => llmService.translateBatch(any(),
            cancelToken: any(named: 'cancelToken'))).called(3);
        // The final exhaustion path logs an error with (message, error, stack).
        verify(() => logger.error(any(), any(), any())).called(1);
      });
    });

    test('does NOT retry on LlmAuthenticationException '
        '(wrapped op invoked exactly once, returns Err)', () async {
      final llmService = _MockLlmService();
      final logger = MockLoggingService();
      final handler =
          LlmRetryHandler(llmService: llmService, logger: logger);
      final authError = const LlmAuthenticationException(
        'Invalid API key',
        providerCode: 'openai',
      );

      when(() => llmService.translateBatch(any(),
              cancelToken: any(named: 'cancelToken')))
          .thenAnswer((_) async =>
              Err<LlmResponse, LlmServiceException>(authError));

      final result = await handler.translateWithRetry(
        llmRequest: _buildRequest(),
        batchId: 'batch-auth',
        dioCancelToken: CancelToken(),
        maxRetries: 3,
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<LlmAuthenticationException>());
      verify(() => llmService.translateBatch(any(),
          cancelToken: any(named: 'cancelToken'))).called(1);
      // Critical invariant: no backoff warning when a non-retryable error
      // is returned on the first attempt.
      verifyNever(() => logger.warning(any()));
      verifyNever(() => logger.warning(any(), any()));
    });

    test('retries on LlmServerException (5xx) and returns Ok on success; '
        'uses exponential backoff (2s on first retry)', () {
      fakeAsync((async) {
        final llmService = _MockLlmService();
        final logger = MockLoggingService();
        final handler =
            LlmRetryHandler(llmService: llmService, logger: logger);
        final serverError = const LlmServerException(
          'Upstream overloaded',
          providerCode: 'openai',
          statusCode: 529,
        );
        final response = _buildResponse();

        var callCount = 0;
        when(() => llmService.translateBatch(any(),
            cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return Err<LlmResponse, LlmServiceException>(serverError);
          }
          return Ok<LlmResponse, LlmServiceException>(response);
        });

        Result<LlmResponse, LlmServiceException>? resolved;
        handler
            .translateWithRetry(
          llmRequest: _buildRequest(),
          batchId: 'batch-5xx',
          dioCancelToken: CancelToken(),
          maxRetries: 3,
        )
            .then((r) {
          resolved = r;
        });

        async.flushMicrotasks();
        expect(callCount, 1);
        expect(resolved, isNull);

        // Exponential backoff for attempt=0 is (1 << 0) * 2 = 2s.
        // Just before 2s, retry must not have fired yet.
        async.elapse(const Duration(milliseconds: 1999));
        expect(callCount, 1);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();
        expect(callCount, 2);
        expect(resolved, isNotNull);
        expect(resolved!.isOk, isTrue);
      });
    });

    test('emits one logger.warning per retry iteration '
        '(two rate-limit errors => two warnings, then success)', () {
      fakeAsync((async) {
        final llmService = _MockLlmService();
        final logger = MockLoggingService();
        final handler =
            LlmRetryHandler(llmService: llmService, logger: logger);
        final rateLimit = const LlmRateLimitException(
          'Rate limit exceeded',
          providerCode: 'openai',
          retryAfterSeconds: 1,
        );
        final response = _buildResponse();

        var callCount = 0;
        when(() => llmService.translateBatch(any(),
            cancelToken: any(named: 'cancelToken'))).thenAnswer((_) async {
          callCount++;
          if (callCount <= 2) {
            return Err<LlmResponse, LlmServiceException>(rateLimit);
          }
          return Ok<LlmResponse, LlmServiceException>(response);
        });

        Result<LlmResponse, LlmServiceException>? resolved;
        handler
            .translateWithRetry(
          llmRequest: _buildRequest(),
          batchId: 'batch-warn',
          dioCancelToken: CancelToken(),
          maxRetries: 3,
        )
            .then((r) {
          resolved = r;
        });

        async.elapse(const Duration(seconds: 30));
        async.flushMicrotasks();

        expect(resolved, isNotNull);
        expect(resolved!.isOk, isTrue);
        expect(callCount, 3);
        // Handler.warning is invoked with a single positional message arg,
        // so the ILoggingService signature `warning(String, [dynamic data])`
        // binds `data` to null. `any()` still matches, so we capture with
        // `warning(any())` (the `data` slot defaults to null).
        verify(() => logger.warning(any())).called(2);
      });
    });
  });
}
