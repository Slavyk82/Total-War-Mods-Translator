import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/utils/rate_limiter.dart';

void main() {
  RateLimiter make({required int rpm, int? tpm}) {
    final limiter = RateLimiter(requestsPerMinute: rpm, tokensPerMinute: tpm);
    addTearDown(limiter.dispose); // cancel the periodic queue timer
    return limiter;
  }

  group('tryAcquire', () {
    test('succeeds until the request bucket is exhausted', () {
      final limiter = make(rpm: 2);
      expect(limiter.tryAcquire(), isTrue);
      expect(limiter.tryAcquire(), isTrue);
      expect(limiter.tryAcquire(), isFalse); // capacity spent
    });

    test('fails (and refunds the request) when the token bucket is short', () {
      final limiter = make(rpm: 10, tpm: 100);
      // 150 tokens > 100 capacity -> token bucket refuses -> request refunded.
      expect(limiter.tryAcquire(estimatedTokens: 150), isFalse);
      final status = limiter.getStatus();
      expect(status.availableRequests, status.maxRequests); // refunded
    });
  });

  group('acquire guard', () {
    test('rejects a request larger than the token bucket capacity', () {
      final limiter = make(rpm: 10, tpm: 100);
      expect(
        limiter.acquire(estimatedTokens: 200),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('calculateWaitTime / reset', () {
    test('is zero while capacity remains, non-zero once exhausted', () {
      final limiter = make(rpm: 1);
      expect(limiter.calculateWaitTime(), Duration.zero);

      limiter.tryAcquire(); // spend the single slot
      expect(limiter.calculateWaitTime(), greaterThan(Duration.zero));
    });

    test('reset restores capacity', () {
      final limiter = make(rpm: 1);
      limiter.tryAcquire();
      expect(limiter.tryAcquire(), isFalse);

      limiter.reset();
      expect(limiter.tryAcquire(), isTrue);
    });
  });

  group('getStatus', () {
    test('reports request/token capacity and queue length', () {
      final limiter = make(rpm: 5, tpm: 1000);
      final status = limiter.getStatus();
      expect(status.maxRequests, 5);
      expect(status.maxTokens, 1000);
      expect(status.queuedRequests, 0);
    });
  });

  group('RateLimitStatus', () {
    test('utilization and isNearLimit', () {
      const low = RateLimitStatus(
        availableRequests: 10,
        maxRequests: 10,
        queuedRequests: 0,
      );
      expect(low.requestUtilization, 0.0);
      expect(low.tokenUtilization, isNull);
      expect(low.isNearLimit, isFalse);

      const high = RateLimitStatus(
        availableRequests: 0,
        maxRequests: 10,
        availableTokens: 50,
        maxTokens: 1000,
        queuedRequests: 3,
      );
      expect(high.requestUtilization, 1.0);
      expect(high.tokenUtilization, closeTo(0.95, 0.001));
      expect(high.isNearLimit, isTrue);
    });
  });
}
