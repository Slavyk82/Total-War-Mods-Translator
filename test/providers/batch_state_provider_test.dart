import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/translation/batch_state_provider.dart';

void main() {
  group('BatchState', () {
    test('creates with required fields', () {
      const state = BatchState(
        batchId: 'batch-123',
        status: BatchStatus.idle,
      );

      expect(state.batchId, 'batch-123');
      expect(state.status, BatchStatus.idle);
      expect(state.totalUnits, 0);
      expect(state.completedUnits, 0);
      expect(state.failedUnits, 0);
      expect(state.progressPercent, 0.0);
      expect(state.errorMessage, isNull);
      expect(state.startedAt, isNull);
      expect(state.completedAt, isNull);
      expect(state.batchNumber, 0);
      expect(state.projectLanguageId, isNull);
    });

    test('creates with all fields', () {
      final now = DateTime.now();
      final state = BatchState(
        batchId: 'batch-123',
        status: BatchStatus.running,
        totalUnits: 100,
        completedUnits: 50,
        failedUnits: 5,
        progressPercent: 55.0,
        errorMessage: 'Some error',
        startedAt: now,
        completedAt: now.add(const Duration(hours: 1)),
        batchNumber: 3,
        projectLanguageId: 'lang-456',
      );

      expect(state.batchId, 'batch-123');
      expect(state.status, BatchStatus.running);
      expect(state.totalUnits, 100);
      expect(state.completedUnits, 50);
      expect(state.failedUnits, 5);
      expect(state.progressPercent, 55.0);
      expect(state.errorMessage, 'Some error');
      expect(state.startedAt, now);
      expect(state.batchNumber, 3);
      expect(state.projectLanguageId, 'lang-456');
    });

    group('copyWith', () {
      test('creates new state with updated status', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.idle,
        );

        final newState = state.copyWith(status: BatchStatus.running);

        expect(state.status, BatchStatus.idle);
        expect(newState.status, BatchStatus.running);
        expect(newState.batchId, 'batch-123');
      });

      test('preserves batchId (immutable)', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.idle,
        );

        final newState = state.copyWith(status: BatchStatus.running);

        expect(newState.batchId, 'batch-123');
      });

      test('updates multiple fields', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.idle,
        );

        final newState = state.copyWith(
          status: BatchStatus.running,
          totalUnits: 100,
          completedUnits: 25,
          progressPercent: 25.0,
        );

        expect(newState.status, BatchStatus.running);
        expect(newState.totalUnits, 100);
        expect(newState.completedUnits, 25);
        expect(newState.progressPercent, 25.0);
      });
    });

    group('isActive', () {
      test('returns true when status is running', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.running,
        );

        expect(state.isActive, isTrue);
      });

      test('returns true when status is paused', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.paused,
        );

        expect(state.isActive, isTrue);
      });

      test('returns false when status is idle', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.idle,
        );

        expect(state.isActive, isFalse);
      });

      test('returns false when status is completed', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.completed,
        );

        expect(state.isActive, isFalse);
      });

      test('returns false when status is failed', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.failed,
        );

        expect(state.isActive, isFalse);
      });

      test('returns false when status is cancelled', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.cancelled,
        );

        expect(state.isActive, isFalse);
      });
    });

    group('isComplete', () {
      test('returns true when status is completed', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.completed,
        );

        expect(state.isComplete, isTrue);
      });

      test('returns true when status is failed', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.failed,
        );

        expect(state.isComplete, isTrue);
      });

      test('returns true when status is cancelled', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.cancelled,
        );

        expect(state.isComplete, isTrue);
      });

      test('returns false when status is running', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.running,
        );

        expect(state.isComplete, isFalse);
      });

      test('returns false when status is idle', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.idle,
        );

        expect(state.isComplete, isFalse);
      });

      test('returns false when status is paused', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.paused,
        );

        expect(state.isComplete, isFalse);
      });
    });

    group('hasErrors', () {
      test('returns true when failedUnits > 0', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.running,
          failedUnits: 1,
        );

        expect(state.hasErrors, isTrue);
      });

      test('returns false when failedUnits is 0', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.running,
          failedUnits: 0,
        );

        expect(state.hasErrors, isFalse);
      });
    });

    group('remainingUnits', () {
      test('calculates correctly', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.running,
          totalUnits: 100,
          completedUnits: 40,
          failedUnits: 10,
        );

        expect(state.remainingUnits, 50);
      });

      test('returns total when nothing processed', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.running,
          totalUnits: 100,
          completedUnits: 0,
          failedUnits: 0,
        );

        expect(state.remainingUnits, 100);
      });

      test('returns 0 when all processed', () {
        const state = BatchState(
          batchId: 'batch-123',
          status: BatchStatus.completed,
          totalUnits: 100,
          completedUnits: 95,
          failedUnits: 5,
        );

        expect(state.remainingUnits, 0);
      });
    });
  });

  group('BatchStatus', () {
    test('has all expected values', () {
      expect(BatchStatus.values, contains(BatchStatus.idle));
      expect(BatchStatus.values, contains(BatchStatus.running));
      expect(BatchStatus.values, contains(BatchStatus.paused));
      expect(BatchStatus.values, contains(BatchStatus.completed));
      expect(BatchStatus.values, contains(BatchStatus.failed));
      expect(BatchStatus.values, contains(BatchStatus.cancelled));
    });

    test('has correct number of values', () {
      expect(BatchStatus.values.length, 6);
    });
  });

  group('BatchState lifecycle simulation', () {
    test('simulates complete batch lifecycle', () {
      // Initial state
      var state = const BatchState(
        batchId: 'batch-lifecycle',
        status: BatchStatus.idle,
      );

      expect(state.isActive, isFalse);
      expect(state.isComplete, isFalse);

      // Start batch
      state = state.copyWith(
        status: BatchStatus.running,
        totalUnits: 100,
        startedAt: DateTime.now(),
        batchNumber: 1,
        projectLanguageId: 'proj-lang-1',
      );

      expect(state.isActive, isTrue);
      expect(state.isComplete, isFalse);
      expect(state.totalUnits, 100);

      // Progress update
      state = state.copyWith(
        completedUnits: 50,
        progressPercent: 50.0,
      );

      expect(state.completedUnits, 50);
      expect(state.remainingUnits, 50);

      // Some failures
      state = state.copyWith(
        completedUnits: 75,
        failedUnits: 5,
        progressPercent: 80.0,
      );

      expect(state.hasErrors, isTrue);
      expect(state.remainingUnits, 20);

      // Pause
      state = state.copyWith(status: BatchStatus.paused);

      expect(state.isActive, isTrue);
      expect(state.status, BatchStatus.paused);

      // Resume
      state = state.copyWith(status: BatchStatus.running);

      expect(state.status, BatchStatus.running);

      // Complete
      state = state.copyWith(
        status: BatchStatus.completed,
        completedUnits: 95,
        progressPercent: 100.0,
        completedAt: DateTime.now(),
      );

      expect(state.isActive, isFalse);
      expect(state.isComplete, isTrue);
      expect(state.remainingUnits, 0);
    });

    test('simulates failed batch', () {
      var state = const BatchState(
        batchId: 'batch-failed',
        status: BatchStatus.running,
        totalUnits: 100,
      );

      // Progress
      state = state.copyWith(
        completedUnits: 25,
        progressPercent: 25.0,
      );

      // Failure
      state = state.copyWith(
        status: BatchStatus.failed,
        errorMessage: 'API rate limit exceeded',
        completedAt: DateTime.now(),
      );

      expect(state.isActive, isFalse);
      expect(state.isComplete, isTrue);
      expect(state.errorMessage, 'API rate limit exceeded');
    });

    test('simulates cancelled batch', () {
      var state = const BatchState(
        batchId: 'batch-cancelled',
        status: BatchStatus.running,
        totalUnits: 100,
        completedUnits: 30,
      );

      // Cancel
      state = state.copyWith(
        status: BatchStatus.cancelled,
        completedAt: DateTime.now(),
      );

      expect(state.isActive, isFalse);
      expect(state.isComplete, isTrue);
      expect(state.completedUnits, 30);
      expect(state.remainingUnits, 70);
    });
  });

  group('BatchState edge cases', () {
    test('handles zero total units', () {
      const state = BatchState(
        batchId: 'batch-empty',
        status: BatchStatus.running,
        totalUnits: 0,
      );

      expect(state.remainingUnits, 0);
    });

    test('handles completed units exceeding total (data inconsistency)', () {
      const state = BatchState(
        batchId: 'batch-overflow',
        status: BatchStatus.running,
        totalUnits: 100,
        completedUnits: 110,
        failedUnits: 0,
      );

      // This would result in negative remaining, which shows data issue
      expect(state.remainingUnits, -10);
    });

    test('handles all units failed', () {
      const state = BatchState(
        batchId: 'batch-all-failed',
        status: BatchStatus.failed,
        totalUnits: 100,
        completedUnits: 0,
        failedUnits: 100,
      );

      expect(state.hasErrors, isTrue);
      expect(state.remainingUnits, 0);
      expect(state.isComplete, isTrue);
    });

    test('handles large batch numbers', () {
      const state = BatchState(
        batchId: 'batch-large',
        status: BatchStatus.running,
        totalUnits: 1000000,
        completedUnits: 500000,
        failedUnits: 1000,
        batchNumber: 999,
      );

      expect(state.remainingUnits, 499000);
    });

    test('preserves DateTime precision', () {
      final startTime = DateTime(2024, 1, 15, 10, 30, 45, 123);
      final endTime = DateTime(2024, 1, 15, 11, 45, 30, 456);

      final state = BatchState(
        batchId: 'batch-time',
        status: BatchStatus.completed,
        startedAt: startTime,
        completedAt: endTime,
      );

      expect(state.startedAt, startTime);
      expect(state.completedAt, endTime);
    });
  });
}
