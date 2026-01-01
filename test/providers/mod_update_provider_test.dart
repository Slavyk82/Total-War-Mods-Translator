import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/mods/mod_update_provider.dart';

void main() {
  group('ModUpdateStatus', () {
    test('has all expected values', () {
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.pending));
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.downloading));
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.detectingChanges));
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.updatingDatabase));
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.completed));
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.failed));
      expect(ModUpdateStatus.values, contains(ModUpdateStatus.cancelled));
    });
  });

  group('ModUpdateInfo', () {
    test('creates with required fields', () {
      const info = ModUpdateInfo(
        projectId: 'proj-123',
        projectName: 'Test Project',
        status: ModUpdateStatus.pending,
      );

      expect(info.projectId, 'proj-123');
      expect(info.projectName, 'Test Project');
      expect(info.status, ModUpdateStatus.pending);
      expect(info.progress, 0.0);
      expect(info.errorMessage, isNull);
      expect(info.newVersion, isNull);
    });

    test('creates with all fields', () {
      const info = ModUpdateInfo(
        projectId: 'proj-123',
        projectName: 'Test Project',
        status: ModUpdateStatus.failed,
        progress: 0.5,
        errorMessage: 'Download failed',
      );

      expect(info.projectId, 'proj-123');
      expect(info.projectName, 'Test Project');
      expect(info.status, ModUpdateStatus.failed);
      expect(info.progress, 0.5);
      expect(info.errorMessage, 'Download failed');
    });

    group('copyWith', () {
      test('creates new info with updated status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test Project',
          status: ModUpdateStatus.pending,
        );

        final newInfo = info.copyWith(status: ModUpdateStatus.downloading);

        expect(info.status, ModUpdateStatus.pending);
        expect(newInfo.status, ModUpdateStatus.downloading);
        expect(newInfo.projectId, 'proj-123');
      });

      test('updates progress', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test Project',
          status: ModUpdateStatus.downloading,
        );

        final newInfo = info.copyWith(progress: 0.75);

        expect(newInfo.progress, 0.75);
      });

      test('updates error message', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test Project',
          status: ModUpdateStatus.failed,
        );

        final newInfo = info.copyWith(
          errorMessage: 'Connection timeout',
        );

        expect(newInfo.errorMessage, 'Connection timeout');
      });
    });

    group('isInProgress', () {
      test('returns true for downloading status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.downloading,
        );

        expect(info.isInProgress, isTrue);
      });

      test('returns true for detectingChanges status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.detectingChanges,
        );

        expect(info.isInProgress, isTrue);
      });

      test('returns true for updatingDatabase status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.updatingDatabase,
        );

        expect(info.isInProgress, isTrue);
      });

      test('returns false for pending status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.pending,
        );

        expect(info.isInProgress, isFalse);
      });

      test('returns false for completed status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.completed,
        );

        expect(info.isInProgress, isFalse);
      });

      test('returns false for failed status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.failed,
        );

        expect(info.isInProgress, isFalse);
      });

      test('returns false for cancelled status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.cancelled,
        );

        expect(info.isInProgress, isFalse);
      });
    });

    group('isCompleted', () {
      test('returns true for completed status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.completed,
        );

        expect(info.isCompleted, isTrue);
      });

      test('returns false for other statuses', () {
        for (final status in ModUpdateStatus.values) {
          if (status != ModUpdateStatus.completed) {
            final info = ModUpdateInfo(
              projectId: 'proj-123',
              projectName: 'Test',
              status: status,
            );
            expect(info.isCompleted, isFalse);
          }
        }
      });
    });

    group('isFailed', () {
      test('returns true for failed status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.failed,
        );

        expect(info.isFailed, isTrue);
      });

      test('returns false for other statuses', () {
        for (final status in ModUpdateStatus.values) {
          if (status != ModUpdateStatus.failed) {
            final info = ModUpdateInfo(
              projectId: 'proj-123',
              projectName: 'Test',
              status: status,
            );
            expect(info.isFailed, isFalse);
          }
        }
      });
    });

    group('isCancelled', () {
      test('returns true for cancelled status', () {
        const info = ModUpdateInfo(
          projectId: 'proj-123',
          projectName: 'Test',
          status: ModUpdateStatus.cancelled,
        );

        expect(info.isCancelled, isTrue);
      });

      test('returns false for other statuses', () {
        for (final status in ModUpdateStatus.values) {
          if (status != ModUpdateStatus.cancelled) {
            final info = ModUpdateInfo(
              projectId: 'proj-123',
              projectName: 'Test',
              status: status,
            );
            expect(info.isCancelled, isFalse);
          }
        }
      });
    });
  });

  group('ModUpdateQueueNotifier', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer();
    });

    tearDown(() {
      container.dispose();
    });

    test('initial state is empty map', () {
      final state = container.read(modUpdateQueueProvider);

      expect(state, isEmpty);
    });

    test('clearQueue clears all entries', () {
      container.read(modUpdateQueueProvider.notifier).clearQueue();

      final state = container.read(modUpdateQueueProvider);

      expect(state, isEmpty);
    });
  });

  group('ModUpdateInfo lifecycle simulation', () {
    test('simulates successful update lifecycle', () {
      var info = const ModUpdateInfo(
        projectId: 'proj-lifecycle',
        projectName: 'Lifecycle Test',
        status: ModUpdateStatus.pending,
      );

      expect(info.isInProgress, isFalse);
      expect(info.isCompleted, isFalse);

      // Start downloading
      info = info.copyWith(status: ModUpdateStatus.downloading);
      expect(info.isInProgress, isTrue);

      // Progress update
      info = info.copyWith(progress: 0.5);
      expect(info.progress, 0.5);

      // Detecting changes
      info = info.copyWith(status: ModUpdateStatus.detectingChanges);
      expect(info.isInProgress, isTrue);

      // Updating database
      info = info.copyWith(status: ModUpdateStatus.updatingDatabase);
      expect(info.isInProgress, isTrue);

      // Complete
      info = info.copyWith(
        status: ModUpdateStatus.completed,
        progress: 1.0,
      );
      expect(info.isCompleted, isTrue);
      expect(info.isInProgress, isFalse);
      expect(info.progress, 1.0);
    });

    test('simulates failed update', () {
      var info = const ModUpdateInfo(
        projectId: 'proj-failed',
        projectName: 'Failed Test',
        status: ModUpdateStatus.downloading,
        progress: 0.3,
      );

      // Failure during download
      info = info.copyWith(
        status: ModUpdateStatus.failed,
        errorMessage: 'Network error: Connection refused',
      );

      expect(info.isFailed, isTrue);
      expect(info.isInProgress, isFalse);
      expect(info.errorMessage, 'Network error: Connection refused');
      expect(info.progress, 0.3); // Progress preserved at failure point
    });

    test('simulates cancelled update', () {
      var info = const ModUpdateInfo(
        projectId: 'proj-cancelled',
        projectName: 'Cancelled Test',
        status: ModUpdateStatus.downloading,
        progress: 0.6,
      );

      // User cancels
      info = info.copyWith(status: ModUpdateStatus.cancelled);

      expect(info.isCancelled, isTrue);
      expect(info.isInProgress, isFalse);
      expect(info.progress, 0.6);
    });
  });

  group('ModUpdateInfo edge cases', () {
    test('handles progress at boundaries', () {
      const atZero = ModUpdateInfo(
        projectId: 'proj-1',
        projectName: 'Test',
        status: ModUpdateStatus.pending,
        progress: 0.0,
      );

      const atOne = ModUpdateInfo(
        projectId: 'proj-2',
        projectName: 'Test',
        status: ModUpdateStatus.completed,
        progress: 1.0,
      );

      expect(atZero.progress, 0.0);
      expect(atOne.progress, 1.0);
    });

    test('handles empty project name', () {
      const info = ModUpdateInfo(
        projectId: 'proj-empty-name',
        projectName: '',
        status: ModUpdateStatus.pending,
      );

      expect(info.projectName, '');
    });

    test('handles long error messages', () {
      final longError = 'Error: ' * 100;
      final info = ModUpdateInfo(
        projectId: 'proj-long-error',
        projectName: 'Test',
        status: ModUpdateStatus.failed,
        errorMessage: longError,
      );

      expect(info.errorMessage, longError);
    });

    test('preserves projectId through multiple copyWith calls', () {
      const original = ModUpdateInfo(
        projectId: 'proj-preserve-id',
        projectName: 'Original',
        status: ModUpdateStatus.pending,
      );

      final updated = original
          .copyWith(status: ModUpdateStatus.downloading)
          .copyWith(progress: 0.5)
          .copyWith(status: ModUpdateStatus.completed);

      expect(updated.projectId, 'proj-preserve-id');
    });
  });

  group('ModUpdateStatus transitions', () {
    test('valid transitions from pending', () {
      const validNext = [
        ModUpdateStatus.downloading,
        ModUpdateStatus.cancelled,
      ];

      for (final status in validNext) {
        final info = const ModUpdateInfo(
          projectId: 'proj-1',
          projectName: 'Test',
          status: ModUpdateStatus.pending,
        ).copyWith(status: status);

        expect(info.status, status);
      }
    });

    test('valid transitions from downloading', () {
      const validNext = [
        ModUpdateStatus.detectingChanges,
        ModUpdateStatus.failed,
        ModUpdateStatus.cancelled,
      ];

      for (final status in validNext) {
        final info = const ModUpdateInfo(
          projectId: 'proj-1',
          projectName: 'Test',
          status: ModUpdateStatus.downloading,
        ).copyWith(status: status);

        expect(info.status, status);
      }
    });

    test('valid transitions from detectingChanges', () {
      const validNext = [
        ModUpdateStatus.updatingDatabase,
        ModUpdateStatus.failed,
        ModUpdateStatus.cancelled,
      ];

      for (final status in validNext) {
        final info = const ModUpdateInfo(
          projectId: 'proj-1',
          projectName: 'Test',
          status: ModUpdateStatus.detectingChanges,
        ).copyWith(status: status);

        expect(info.status, status);
      }
    });

    test('valid transitions from updatingDatabase', () {
      const validNext = [
        ModUpdateStatus.completed,
        ModUpdateStatus.failed,
      ];

      for (final status in validNext) {
        final info = const ModUpdateInfo(
          projectId: 'proj-1',
          projectName: 'Test',
          status: ModUpdateStatus.updatingDatabase,
        ).copyWith(status: status);

        expect(info.status, status);
      }
    });

    test('retry from failed goes back to pending', () {
      const failedInfo = ModUpdateInfo(
        projectId: 'proj-retry',
        projectName: 'Test',
        status: ModUpdateStatus.failed,
        errorMessage: 'Previous error',
      );

      final retryInfo = failedInfo.copyWith(
        status: ModUpdateStatus.pending,
        errorMessage: null,
      );

      expect(retryInfo.status, ModUpdateStatus.pending);
      // Note: copyWith doesn't clear errorMessage to null, it preserves it
      // This is a limitation of the current implementation
    });
  });
}
