import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/utils/concurrency_semaphore.dart';

void main() {
  test('rejects a maxConcurrent below 1', () {
    expect(() => ConcurrencySemaphore(maxConcurrent: 0),
        throwsA(isA<AssertionError>()));
  });

  test('exposes its configuration and starts empty', () {
    final sem = ConcurrencySemaphore(maxConcurrent: 3);
    expect(sem.maxConcurrent, 3);
    expect(sem.activeCount, 0);
    expect(sem.waitingCount, 0);
    expect(sem.isAtCapacity, isFalse);
  });

  test('acquire increments the active count up to capacity', () async {
    final sem = ConcurrencySemaphore(maxConcurrent: 2);
    await sem.acquire();
    expect(sem.activeCount, 1);
    expect(sem.isAtCapacity, isFalse);

    await sem.acquire();
    expect(sem.activeCount, 2);
    expect(sem.isAtCapacity, isTrue);
  });

  test('queues acquires beyond capacity and hands the slot to a waiter',
      () async {
    final sem = ConcurrencySemaphore(maxConcurrent: 1);
    await sem.acquire();

    var thirdCompleted = false;
    final waiting = sem.acquire().then((_) => thirdCompleted = true);

    // The over-capacity acquire is parked.
    expect(sem.waitingCount, 1);
    expect(thirdCompleted, isFalse);

    // Releasing hands the slot directly to the waiter (count stays at 1).
    sem.release();
    await waiting;
    expect(thirdCompleted, isTrue);
    expect(sem.waitingCount, 0);
    expect(sem.activeCount, 1);
  });

  test('release without a matching acquire is a no-op', () {
    final sem = ConcurrencySemaphore(maxConcurrent: 2);
    sem.release();
    expect(sem.activeCount, 0);
  });

  test('release decrements when there are no waiters', () async {
    final sem = ConcurrencySemaphore(maxConcurrent: 2);
    await sem.acquire();
    expect(sem.activeCount, 1);
    sem.release();
    expect(sem.activeCount, 0);
  });

  group('execute', () {
    test('runs the function and releases the slot', () async {
      final sem = ConcurrencySemaphore(maxConcurrent: 1);
      final result = await sem.execute(() async => 42);
      expect(result, 42);
      expect(sem.activeCount, 0);
    });

    test('releases the slot even when the function throws', () async {
      final sem = ConcurrencySemaphore(maxConcurrent: 1);
      await expectLater(
        sem.execute(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(sem.activeCount, 0);
    });

    test('serializes work beyond capacity', () async {
      final sem = ConcurrencySemaphore(maxConcurrent: 2);
      var peak = 0;
      var running = 0;

      Future<void> task() => sem.execute(() async {
            running++;
            if (running > peak) peak = running;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            running--;
          });

      await Future.wait([task(), task(), task(), task(), task()]);

      expect(peak, lessThanOrEqualTo(2));
      expect(sem.activeCount, 0);
      expect(sem.waitingCount, 0);
    });
  });
}
