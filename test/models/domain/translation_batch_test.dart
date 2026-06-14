import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_batch.dart';

void main() {
  TranslationBatch makeBatch({
    String id = 'batch-1',
    String projectLanguageId = 'pl-1',
    TranslationBatchStatus status = TranslationBatchStatus.pending,
    String providerId = 'provider-1',
    int batchNumber = 1,
    int unitsCount = 0,
    int unitsCompleted = 0,
    int? startedAt,
    int? completedAt,
    String? errorMessage,
    int retryCount = 0,
  }) {
    return TranslationBatch(
      id: id,
      projectLanguageId: projectLanguageId,
      status: status,
      providerId: providerId,
      batchNumber: batchNumber,
      unitsCount: unitsCount,
      unitsCompleted: unitsCompleted,
      startedAt: startedAt,
      completedAt: completedAt,
      errorMessage: errorMessage,
      retryCount: retryCount,
    );
  }

  group('TranslationBatchStatus enum', () {
    test('has all five values', () {
      expect(TranslationBatchStatus.values, hasLength(5));
      expect(
        TranslationBatchStatus.values,
        containsAll([
          TranslationBatchStatus.pending,
          TranslationBatchStatus.processing,
          TranslationBatchStatus.completed,
          TranslationBatchStatus.failed,
          TranslationBatchStatus.cancelled,
        ]),
      );
    });
  });

  group('constructor', () {
    test('uses default values for optional fields', () {
      const batch = TranslationBatch(
        id: 'id',
        projectLanguageId: 'pl',
        providerId: 'prov',
        batchNumber: 3,
      );
      expect(batch.status, TranslationBatchStatus.pending);
      expect(batch.unitsCount, 0);
      expect(batch.unitsCompleted, 0);
      expect(batch.startedAt, isNull);
      expect(batch.completedAt, isNull);
      expect(batch.errorMessage, isNull);
      expect(batch.retryCount, 0);
    });

    test('stores provided values', () {
      final batch = makeBatch(
        id: 'a',
        projectLanguageId: 'b',
        status: TranslationBatchStatus.processing,
        providerId: 'c',
        batchNumber: 7,
        unitsCount: 10,
        unitsCompleted: 4,
        startedAt: 100,
        completedAt: 200,
        errorMessage: 'oops',
        retryCount: 2,
      );
      expect(batch.id, 'a');
      expect(batch.projectLanguageId, 'b');
      expect(batch.status, TranslationBatchStatus.processing);
      expect(batch.providerId, 'c');
      expect(batch.batchNumber, 7);
      expect(batch.unitsCount, 10);
      expect(batch.unitsCompleted, 4);
      expect(batch.startedAt, 100);
      expect(batch.completedAt, 200);
      expect(batch.errorMessage, 'oops');
      expect(batch.retryCount, 2);
    });
  });

  group('status boolean getters', () {
    test('isPending', () {
      expect(makeBatch(status: TranslationBatchStatus.pending).isPending, isTrue);
      expect(
        makeBatch(status: TranslationBatchStatus.processing).isPending,
        isFalse,
      );
    });

    test('isProcessing', () {
      expect(
        makeBatch(status: TranslationBatchStatus.processing).isProcessing,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.pending).isProcessing,
        isFalse,
      );
    });

    test('isCompleted', () {
      expect(
        makeBatch(status: TranslationBatchStatus.completed).isCompleted,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.pending).isCompleted,
        isFalse,
      );
    });

    test('isFailed', () {
      expect(makeBatch(status: TranslationBatchStatus.failed).isFailed, isTrue);
      expect(
        makeBatch(status: TranslationBatchStatus.pending).isFailed,
        isFalse,
      );
    });

    test('isCancelled', () {
      expect(
        makeBatch(status: TranslationBatchStatus.cancelled).isCancelled,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.pending).isCancelled,
        isFalse,
      );
    });

    test('isFinished is true for completed/failed/cancelled', () {
      expect(
        makeBatch(status: TranslationBatchStatus.completed).isFinished,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.failed).isFinished,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.cancelled).isFinished,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.pending).isFinished,
        isFalse,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.processing).isFinished,
        isFalse,
      );
    });

    test('isActive is true for pending/processing', () {
      expect(
        makeBatch(status: TranslationBatchStatus.pending).isActive,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.processing).isActive,
        isTrue,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.completed).isActive,
        isFalse,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.failed).isActive,
        isFalse,
      );
      expect(
        makeBatch(status: TranslationBatchStatus.cancelled).isActive,
        isFalse,
      );
    });
  });

  group('other boolean getters', () {
    test('hasError', () {
      expect(makeBatch(errorMessage: 'x').hasError, isTrue);
      expect(makeBatch(errorMessage: null).hasError, isFalse);
      expect(makeBatch(errorMessage: '').hasError, isFalse);
    });

    test('hasBeenRetried', () {
      expect(makeBatch(retryCount: 0).hasBeenRetried, isFalse);
      expect(makeBatch(retryCount: 1).hasBeenRetried, isTrue);
    });

    test('hasStarted', () {
      expect(makeBatch(startedAt: null).hasStarted, isFalse);
      expect(makeBatch(startedAt: 123).hasStarted, isTrue);
    });
  });

  group('progress getters', () {
    test('progressPercent returns 0 when unitsCount is 0', () {
      expect(makeBatch(unitsCount: 0).progressPercent, 0.0);
    });

    test('progressPercent computes percentage', () {
      expect(
        makeBatch(unitsCount: 30, unitsCompleted: 15).progressPercent,
        50.0,
      );
    });

    test('progressPercentInt rounds', () {
      expect(
        makeBatch(unitsCount: 3, unitsCompleted: 1).progressPercentInt,
        33,
      );
    });

    test('remainingUnits', () {
      expect(
        makeBatch(unitsCount: 30, unitsCompleted: 12).remainingUnits,
        18,
      );
    });

    test('allUnitsCompleted', () {
      expect(
        makeBatch(unitsCount: 5, unitsCompleted: 5).allUnitsCompleted,
        isTrue,
      );
      expect(
        makeBatch(unitsCount: 5, unitsCompleted: 6).allUnitsCompleted,
        isTrue,
      );
      expect(
        makeBatch(unitsCount: 5, unitsCompleted: 4).allUnitsCompleted,
        isFalse,
      );
      // unitsCount == 0 => false even though completed >= count
      expect(
        makeBatch(unitsCount: 0, unitsCompleted: 0).allUnitsCompleted,
        isFalse,
      );
    });

    test('progressDisplay formats string', () {
      expect(
        makeBatch(unitsCount: 30, unitsCompleted: 15).progressDisplay,
        '15/30 (50%)',
      );
    });
  });

  group('processingDuration', () {
    test('returns null when not started', () {
      expect(makeBatch(startedAt: null).processingDuration, isNull);
    });

    test('uses completedAt when available', () {
      expect(
        makeBatch(startedAt: 100, completedAt: 250).processingDuration,
        150,
      );
    });

    test('uses now when not completed', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final duration = makeBatch(
        startedAt: nowSec - 10,
        completedAt: null,
      ).processingDuration;
      expect(duration, isNotNull);
      expect(duration, greaterThanOrEqualTo(10));
      expect(duration, lessThan(60));
    });
  });

  group('statusDisplay', () {
    test('maps each status', () {
      expect(
        makeBatch(status: TranslationBatchStatus.pending).statusDisplay,
        'Pending',
      );
      expect(
        makeBatch(status: TranslationBatchStatus.processing).statusDisplay,
        'Processing',
      );
      expect(
        makeBatch(status: TranslationBatchStatus.completed).statusDisplay,
        'Completed',
      );
      expect(
        makeBatch(status: TranslationBatchStatus.failed).statusDisplay,
        'Failed',
      );
      expect(
        makeBatch(status: TranslationBatchStatus.cancelled).statusDisplay,
        'Cancelled',
      );
    });
  });

  group('copyWith', () {
    final base = makeBatch(
      id: 'a',
      projectLanguageId: 'b',
      status: TranslationBatchStatus.pending,
      providerId: 'c',
      batchNumber: 1,
      unitsCount: 10,
      unitsCompleted: 2,
      startedAt: 100,
      completedAt: 200,
      errorMessage: 'err',
      retryCount: 1,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(
        base.copyWith(projectLanguageId: 'z').projectLanguageId,
        'z',
      );
      expect(
        base.copyWith(status: TranslationBatchStatus.failed).status,
        TranslationBatchStatus.failed,
      );
      expect(base.copyWith(providerId: 'z').providerId, 'z');
      expect(base.copyWith(batchNumber: 99).batchNumber, 99);
      expect(base.copyWith(unitsCount: 99).unitsCount, 99);
      expect(base.copyWith(unitsCompleted: 99).unitsCompleted, 99);
      expect(base.copyWith(startedAt: 999).startedAt, 999);
      expect(base.copyWith(completedAt: 999).completedAt, 999);
      expect(base.copyWith(errorMessage: 'new').errorMessage, 'new');
      expect(base.copyWith(retryCount: 9).retryCount, 9);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(id: 'z');
      expect(copy.projectLanguageId, base.projectLanguageId);
      expect(copy.status, base.status);
      expect(copy.providerId, base.providerId);
      expect(copy.batchNumber, base.batchNumber);
      expect(copy.unitsCount, base.unitsCount);
      expect(copy.unitsCompleted, base.unitsCompleted);
      expect(copy.startedAt, base.startedAt);
      expect(copy.completedAt, base.completedAt);
      expect(copy.errorMessage, base.errorMessage);
      expect(copy.retryCount, base.retryCount);
    });
  });

  group('JSON', () {
    final full = makeBatch(
      id: 'a',
      projectLanguageId: 'b',
      status: TranslationBatchStatus.processing,
      providerId: 'c',
      batchNumber: 5,
      unitsCount: 20,
      unitsCompleted: 8,
      startedAt: 1000,
      completedAt: 2000,
      errorMessage: 'boom',
      retryCount: 3,
    );

    test('toJson uses snake_case keys', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['project_language_id'], 'b');
      expect(json['status'], 'processing');
      expect(json['provider_id'], 'c');
      expect(json['batch_number'], 5);
      expect(json['units_count'], 20);
      expect(json['units_completed'], 8);
      expect(json['started_at'], 1000);
      expect(json['completed_at'], 2000);
      expect(json['error_message'], 'boom');
      expect(json['retry_count'], 3);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded =
          TranslationBatch.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = TranslationBatch.fromJson({
        'id': 'a',
        'project_language_id': 'b',
        'provider_id': 'c',
        'batch_number': 2,
      });
      expect(decoded.status, TranslationBatchStatus.pending);
      expect(decoded.unitsCount, 0);
      expect(decoded.unitsCompleted, 0);
      expect(decoded.startedAt, isNull);
      expect(decoded.completedAt, isNull);
      expect(decoded.errorMessage, isNull);
      expect(decoded.retryCount, 0);
    });

    test('fromJson decodes each status value', () {
      for (final entry in {
        'pending': TranslationBatchStatus.pending,
        'processing': TranslationBatchStatus.processing,
        'completed': TranslationBatchStatus.completed,
        'failed': TranslationBatchStatus.failed,
        'cancelled': TranslationBatchStatus.cancelled,
      }.entries) {
        final decoded = TranslationBatch.fromJson({
          'id': 'a',
          'project_language_id': 'b',
          'provider_id': 'c',
          'batch_number': 1,
          'status': entry.key,
        });
        expect(decoded.status, entry.value);
      }
    });
  });

  group('equality and hashCode', () {
    final a = makeBatch(
      id: 'a',
      projectLanguageId: 'b',
      status: TranslationBatchStatus.processing,
      providerId: 'c',
      batchNumber: 5,
      unitsCount: 20,
      unitsCompleted: 8,
      startedAt: 1000,
      completedAt: 2000,
      errorMessage: 'boom',
      retryCount: 3,
    );

    test('identical instance is equal', () {
      expect(a == a, isTrue);
    });

    test('equal field-for-field copies are equal with same hashCode', () {
      final b = a.copyWith();
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('differs when any field differs', () {
      expect(a == a.copyWith(id: 'z'), isFalse);
      expect(a == a.copyWith(projectLanguageId: 'z'), isFalse);
      expect(
        a == a.copyWith(status: TranslationBatchStatus.failed),
        isFalse,
      );
      expect(a == a.copyWith(providerId: 'z'), isFalse);
      expect(a == a.copyWith(batchNumber: 99), isFalse);
      expect(a == a.copyWith(unitsCount: 99), isFalse);
      expect(a == a.copyWith(unitsCompleted: 99), isFalse);
      expect(a == a.copyWith(startedAt: 9999), isFalse);
      expect(a == a.copyWith(completedAt: 9999), isFalse);
      expect(a == a.copyWith(errorMessage: 'other'), isFalse);
      expect(a == a.copyWith(retryCount: 99), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, batchNumber, status and progress', () {
      final batch = makeBatch(
        id: 'a',
        batchNumber: 5,
        status: TranslationBatchStatus.processing,
        unitsCount: 30,
        unitsCompleted: 15,
      );
      expect(
        batch.toString(),
        'TranslationBatch(id: a, batchNumber: 5, '
        'status: TranslationBatchStatus.processing, progress: 15/30 (50%))',
      );
    });
  });
}
