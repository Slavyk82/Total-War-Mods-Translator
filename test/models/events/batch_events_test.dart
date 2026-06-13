import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/batch_events.dart';

void main() {
  group('BatchStartedEvent', () {
    test('constructs and exposes fields', () {
      final event = BatchStartedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        providerId: 'openai',
        batchNumber: 2,
        totalUnits: 50,
      );

      expect(event.batchId, 'b1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.providerId, 'openai');
      expect(event.batchNumber, 2);
      expect(event.totalUnits, 50);

      // Inherited from DomainEvent.now()
      expect(event.eventId, isNotEmpty);
      expect(event.timestamp, isA<DateTime>());
      expect(event.eventType, 'BatchStartedEvent');
      expect(event.occurredAt, event.timestamp);
    });

    test('toJson contains all keys', () {
      final event = BatchStartedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        providerId: 'openai',
        batchNumber: 2,
        totalUnits: 50,
      );

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['projectLanguageId'], 'pl1');
      expect(json['providerId'], 'openai');
      expect(json['batchNumber'], 2);
      expect(json['totalUnits'], 50);
    });

    test('toString includes key fields', () {
      final event = BatchStartedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        providerId: 'openai',
        batchNumber: 2,
        totalUnits: 50,
      );

      expect(
        event.toString(),
        'BatchStartedEvent(batchId: b1, number: 2, units: 50)',
      );
    });

    test('unique eventIds across instances', () {
      final a = BatchStartedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        providerId: 'p',
        batchNumber: 1,
        totalUnits: 1,
      );
      final b = BatchStartedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        providerId: 'p',
        batchNumber: 1,
        totalUnits: 1,
      );
      expect(a.eventId, isNot(b.eventId));
    });
  });

  group('BatchProgressEvent', () {
    test('computes progressPercent with non-zero total', () {
      final event = BatchProgressEvent(
        batchId: 'b1',
        totalUnits: 100,
        completedUnits: 25,
        failedUnits: 5,
      );

      expect(event.progressPercent, 25.0);
      expect(event.remainingUnits, 100 - 25 - 5);
    });

    test('progressPercent is 0 when totalUnits is 0', () {
      final event = BatchProgressEvent(
        batchId: 'b1',
        totalUnits: 0,
        completedUnits: 0,
        failedUnits: 0,
      );

      expect(event.progressPercent, 0);
      expect(event.remainingUnits, 0);
    });

    test('toJson contains all keys', () {
      final event = BatchProgressEvent(
        batchId: 'b1',
        totalUnits: 100,
        completedUnits: 50,
        failedUnits: 10,
      );

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['totalUnits'], 100);
      expect(json['completedUnits'], 50);
      expect(json['failedUnits'], 10);
      expect(json['progressPercent'], 50.0);
    });

    test('toString includes formatted progress', () {
      final event = BatchProgressEvent(
        batchId: 'b1',
        totalUnits: 100,
        completedUnits: 50,
        failedUnits: 10,
      );

      expect(
        event.toString(),
        'BatchProgressEvent(batchId: b1, progress: 50.0%, '
        'completed: 50/100, failed: 10)',
      );
    });
  });

  group('BatchCompletedEvent', () {
    test('constructs and exposes fields', () {
      final event = BatchCompletedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 3,
        totalUnits: 100,
        completedUnits: 90,
        failedUnits: 10,
        processingDuration: const Duration(seconds: 30),
      );

      expect(event.batchId, 'b1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.batchNumber, 3);
      expect(event.totalUnits, 100);
      expect(event.completedUnits, 90);
      expect(event.failedUnits, 10);
      expect(event.processingDuration, const Duration(seconds: 30));
    });

    test('hasFailures true when failedUnits > 0', () {
      final event = BatchCompletedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 1,
        totalUnits: 10,
        completedUnits: 8,
        failedUnits: 2,
        processingDuration: const Duration(seconds: 1),
      );
      expect(event.hasFailures, isTrue);
    });

    test('hasFailures false when failedUnits == 0', () {
      final event = BatchCompletedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 1,
        totalUnits: 10,
        completedUnits: 10,
        failedUnits: 0,
        processingDuration: const Duration(seconds: 1),
      );
      expect(event.hasFailures, isFalse);
      expect(event.successRate, 100.0);
    });

    test('successRate is 0 when totalUnits is 0', () {
      final event = BatchCompletedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 1,
        totalUnits: 0,
        completedUnits: 0,
        failedUnits: 0,
        processingDuration: Duration.zero,
      );
      expect(event.successRate, 0);
    });

    test('toJson contains all keys including durationMs', () {
      final event = BatchCompletedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 3,
        totalUnits: 100,
        completedUnits: 90,
        failedUnits: 10,
        processingDuration: const Duration(milliseconds: 1500),
      );

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['projectLanguageId'], 'pl1');
      expect(json['batchNumber'], 3);
      expect(json['totalUnits'], 100);
      expect(json['completedUnits'], 90);
      expect(json['failedUnits'], 10);
      expect(json['processingDurationMs'], 1500);
    });

    test('toString includes success rate and seconds', () {
      final event = BatchCompletedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 3,
        totalUnits: 100,
        completedUnits: 90,
        failedUnits: 10,
        processingDuration: const Duration(seconds: 30),
      );

      expect(
        event.toString(),
        'BatchCompletedEvent(batchId: b1, success: 90.0%, duration: 30s)',
      );
    });
  });

  group('BatchFailedEvent', () {
    test('constructs and exposes fields', () {
      final event = BatchFailedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 4,
        errorMessage: 'boom',
        completedBeforeFailure: 5,
        totalUnits: 20,
        retryCount: 1,
      );

      expect(event.batchId, 'b1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.batchNumber, 4);
      expect(event.errorMessage, 'boom');
      expect(event.completedBeforeFailure, 5);
      expect(event.totalUnits, 20);
      expect(event.retryCount, 1);
    });

    test('canRetry true when retryCount < 3', () {
      final event = BatchFailedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 1,
        errorMessage: 'e',
        completedBeforeFailure: 0,
        totalUnits: 1,
        retryCount: 2,
      );
      expect(event.canRetry, isTrue);
    });

    test('canRetry false when retryCount >= 3', () {
      final event = BatchFailedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 1,
        errorMessage: 'e',
        completedBeforeFailure: 0,
        totalUnits: 1,
        retryCount: 3,
      );
      expect(event.canRetry, isFalse);
    });

    test('toJson contains all keys', () {
      final event = BatchFailedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 4,
        errorMessage: 'boom',
        completedBeforeFailure: 5,
        totalUnits: 20,
        retryCount: 1,
      );

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['projectLanguageId'], 'pl1');
      expect(json['batchNumber'], 4);
      expect(json['errorMessage'], 'boom');
      expect(json['completedBeforeFailure'], 5);
      expect(json['totalUnits'], 20);
      expect(json['retryCount'], 1);
    });

    test('toString includes error and retries', () {
      final event = BatchFailedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        batchNumber: 4,
        errorMessage: 'boom',
        completedBeforeFailure: 5,
        totalUnits: 20,
        retryCount: 1,
      );

      expect(
        event.toString(),
        'BatchFailedEvent(batchId: b1, error: boom, '
        'completed: 5/20, retries: 1)',
      );
    });
  });

  group('BatchPausedEvent', () {
    test('constructs, toJson and toString', () {
      final event = BatchPausedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 7,
        totalUnits: 30,
      );

      expect(event.batchId, 'b1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.completedUnits, 7);
      expect(event.totalUnits, 30);

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['projectLanguageId'], 'pl1');
      expect(json['completedUnits'], 7);
      expect(json['totalUnits'], 30);

      expect(
        event.toString(),
        'BatchPausedEvent(batchId: b1, completed: 7/30)',
      );
    });
  });

  group('BatchResumedEvent', () {
    test('constructs, toJson and toString', () {
      final event = BatchResumedEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 7,
        totalUnits: 30,
      );

      expect(event.batchId, 'b1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.completedUnits, 7);
      expect(event.totalUnits, 30);

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['projectLanguageId'], 'pl1');
      expect(json['completedUnits'], 7);
      expect(json['totalUnits'], 30);

      expect(
        event.toString(),
        'BatchResumedEvent(batchId: b1, completed: 7/30)',
      );
    });
  });

  group('BatchCancelledEvent', () {
    test('constructs and exposes fields plus getters', () {
      final event = BatchCancelledEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 12,
        totalUnits: 40,
        reason: 'user cancelled',
      );

      expect(event.batchId, 'b1');
      expect(event.projectLanguageId, 'pl1');
      expect(event.completedUnits, 12);
      expect(event.totalUnits, 40);
      expect(event.reason, 'user cancelled');
      expect(event.completedBeforeCancellation, 12);
      expect(event.batchNumber, 0);
    });

    test('toJson contains all keys', () {
      final event = BatchCancelledEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 12,
        totalUnits: 40,
        reason: 'user cancelled',
      );

      final json = event.toJson();
      expect(json['eventId'], event.eventId);
      expect(json['timestamp'], event.timestamp.toIso8601String());
      expect(json['batchId'], 'b1');
      expect(json['projectLanguageId'], 'pl1');
      expect(json['completedUnits'], 12);
      expect(json['totalUnits'], 40);
      expect(json['reason'], 'user cancelled');
    });

    test('toString includes reason', () {
      final event = BatchCancelledEvent(
        batchId: 'b1',
        projectLanguageId: 'pl1',
        completedUnits: 12,
        totalUnits: 40,
        reason: 'user cancelled',
      );

      expect(
        event.toString(),
        'BatchCancelledEvent(batchId: b1, reason: user cancelled, '
        'completed: 12/40)',
      );
    });
  });
}
