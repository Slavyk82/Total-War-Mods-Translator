import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_batch_unit.dart';

void main() {
  TranslationBatchUnit makeUnit({
    String id = 'tbu-1',
    String batchId = 'batch-1',
    String unitId = 'unit-1',
    int processingOrder = 1,
    TranslationBatchUnitStatus status = TranslationBatchUnitStatus.pending,
    String? errorMessage,
    int? startedAt,
    int? completedAt,
  }) {
    return TranslationBatchUnit(
      id: id,
      batchId: batchId,
      unitId: unitId,
      processingOrder: processingOrder,
      status: status,
      errorMessage: errorMessage,
      startedAt: startedAt,
      completedAt: completedAt,
    );
  }

  group('TranslationBatchUnitStatus enum', () {
    test('has all four values', () {
      expect(TranslationBatchUnitStatus.values, hasLength(4));
      expect(
        TranslationBatchUnitStatus.values,
        containsAll([
          TranslationBatchUnitStatus.pending,
          TranslationBatchUnitStatus.processing,
          TranslationBatchUnitStatus.completed,
          TranslationBatchUnitStatus.failed,
        ]),
      );
    });
  });

  group('constructor', () {
    test('uses default values for optional fields', () {
      const unit = TranslationBatchUnit(
        id: 'id',
        batchId: 'b',
        unitId: 'u',
        processingOrder: 3,
      );
      expect(unit.status, TranslationBatchUnitStatus.pending);
      expect(unit.errorMessage, isNull);
      expect(unit.startedAt, isNull);
      expect(unit.completedAt, isNull);
    });
  });

  group('status boolean getters', () {
    test('isPending', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).isPending,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.processing).isPending,
        isFalse,
      );
    });

    test('isProcessing', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.processing).isProcessing,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).isProcessing,
        isFalse,
      );
    });

    test('isCompleted', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.completed).isCompleted,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).isCompleted,
        isFalse,
      );
    });

    test('isFailed', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.failed).isFailed,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).isFailed,
        isFalse,
      );
    });

    test('isFinished is true for completed/failed only', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.completed).isFinished,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.failed).isFinished,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).isFinished,
        isFalse,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.processing).isFinished,
        isFalse,
      );
    });

    test('isActive is true for pending/processing only', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).isActive,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.processing).isActive,
        isTrue,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.completed).isActive,
        isFalse,
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.failed).isActive,
        isFalse,
      );
    });
  });

  group('other boolean getters', () {
    test('hasError', () {
      expect(makeUnit(errorMessage: 'boom').hasError, isTrue);
      expect(makeUnit(errorMessage: null).hasError, isFalse);
      expect(makeUnit(errorMessage: '').hasError, isFalse);
    });

    test('hasStarted', () {
      expect(makeUnit(startedAt: 100).hasStarted, isTrue);
      expect(makeUnit(startedAt: null).hasStarted, isFalse);
    });

    test('hasCompleted', () {
      expect(makeUnit(completedAt: 100).hasCompleted, isTrue);
      expect(makeUnit(completedAt: null).hasCompleted, isFalse);
    });
  });

  group('processingDuration', () {
    test('returns null when not started or not completed', () {
      expect(makeUnit(startedAt: null, completedAt: 100).processingDuration,
          isNull);
      expect(makeUnit(startedAt: 100, completedAt: null).processingDuration,
          isNull);
    });

    test('computes completedAt - startedAt', () {
      expect(
        makeUnit(startedAt: 100, completedAt: 250).processingDuration,
        150,
      );
    });
  });

  group('currentProcessingDuration', () {
    test('returns null when not started', () {
      expect(makeUnit(startedAt: null).currentProcessingDuration, isNull);
    });

    test('uses completedAt when available', () {
      expect(
        makeUnit(startedAt: 100, completedAt: 250).currentProcessingDuration,
        150,
      );
    });

    test('uses now when not completed', () {
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final duration = makeUnit(
        startedAt: nowSec - 10,
        completedAt: null,
      ).currentProcessingDuration;
      expect(duration, isNotNull);
      expect(duration, greaterThanOrEqualTo(10));
      expect(duration, lessThan(60));
    });
  });

  group('statusDisplay and statusIndicator', () {
    test('statusDisplay maps each status', () {
      expect(
        makeUnit(status: TranslationBatchUnitStatus.pending).statusDisplay,
        'Pending',
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.processing).statusDisplay,
        'Processing',
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.completed).statusDisplay,
        'Completed',
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.failed).statusDisplay,
        'Failed',
      );
    });

    test('statusIndicator maps each status to a distinct symbol', () {
      final indicators = TranslationBatchUnitStatus.values
          .map((s) => makeUnit(status: s).statusIndicator)
          .toList();
      expect(indicators.toSet(), hasLength(4));
      expect(
        makeUnit(status: TranslationBatchUnitStatus.completed).statusIndicator,
        '✓',
      );
      expect(
        makeUnit(status: TranslationBatchUnitStatus.failed).statusIndicator,
        '✗',
      );
    });
  });

  group('copyWith', () {
    final base = makeUnit(
      id: 'a',
      batchId: 'b',
      unitId: 'u',
      processingOrder: 1,
      status: TranslationBatchUnitStatus.pending,
      errorMessage: 'err',
      startedAt: 100,
      completedAt: 200,
    );

    test('no-arg copyWith equals original', () {
      expect(base.copyWith(), base);
    });

    test('overrides each field', () {
      expect(base.copyWith(id: 'z').id, 'z');
      expect(base.copyWith(batchId: 'z').batchId, 'z');
      expect(base.copyWith(unitId: 'z').unitId, 'z');
      expect(base.copyWith(processingOrder: 99).processingOrder, 99);
      expect(
        base.copyWith(status: TranslationBatchUnitStatus.failed).status,
        TranslationBatchUnitStatus.failed,
      );
      expect(base.copyWith(errorMessage: 'new').errorMessage, 'new');
      expect(base.copyWith(startedAt: 999).startedAt, 999);
      expect(base.copyWith(completedAt: 999).completedAt, 999);
    });

    test('unset fields fall back to current values', () {
      final copy = base.copyWith(id: 'z');
      expect(copy.batchId, base.batchId);
      expect(copy.unitId, base.unitId);
      expect(copy.processingOrder, base.processingOrder);
      expect(copy.status, base.status);
      expect(copy.errorMessage, base.errorMessage);
      expect(copy.startedAt, base.startedAt);
      expect(copy.completedAt, base.completedAt);
    });
  });

  group('JSON', () {
    final full = makeUnit(
      id: 'a',
      batchId: 'b',
      unitId: 'u',
      processingOrder: 5,
      status: TranslationBatchUnitStatus.processing,
      errorMessage: 'boom',
      startedAt: 1000,
      completedAt: 2000,
    );

    test('toJson uses snake_case keys', () {
      final json = full.toJson();
      expect(json['id'], 'a');
      expect(json['batch_id'], 'b');
      expect(json['unit_id'], 'u');
      expect(json['processing_order'], 5);
      expect(json['status'], 'processing');
      expect(json['error_message'], 'boom');
      expect(json['started_at'], 1000);
      expect(json['completed_at'], 2000);
    });

    test('round-trips through jsonEncode/jsonDecode', () {
      final encoded = jsonEncode(full.toJson());
      final decoded = TranslationBatchUnit.fromJson(
          jsonDecode(encoded) as Map<String, dynamic>);
      expect(decoded, full);
    });

    test('fromJson applies defaults for missing optional fields', () {
      final decoded = TranslationBatchUnit.fromJson({
        'id': 'a',
        'batch_id': 'b',
        'unit_id': 'u',
        'processing_order': 2,
      });
      expect(decoded.status, TranslationBatchUnitStatus.pending);
      expect(decoded.errorMessage, isNull);
      expect(decoded.startedAt, isNull);
      expect(decoded.completedAt, isNull);
    });

    test('fromJson decodes each status value', () {
      for (final entry in {
        'pending': TranslationBatchUnitStatus.pending,
        'processing': TranslationBatchUnitStatus.processing,
        'completed': TranslationBatchUnitStatus.completed,
        'failed': TranslationBatchUnitStatus.failed,
      }.entries) {
        final decoded = TranslationBatchUnit.fromJson({
          'id': 'a',
          'batch_id': 'b',
          'unit_id': 'u',
          'processing_order': 1,
          'status': entry.key,
        });
        expect(decoded.status, entry.value);
      }
    });
  });

  group('equality and hashCode', () {
    final a = makeUnit(
      id: 'a',
      batchId: 'b',
      unitId: 'u',
      processingOrder: 5,
      status: TranslationBatchUnitStatus.processing,
      errorMessage: 'boom',
      startedAt: 1000,
      completedAt: 2000,
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
      expect(a == a.copyWith(batchId: 'z'), isFalse);
      expect(a == a.copyWith(unitId: 'z'), isFalse);
      expect(a == a.copyWith(processingOrder: 99), isFalse);
      expect(
        a == a.copyWith(status: TranslationBatchUnitStatus.failed),
        isFalse,
      );
      expect(a == a.copyWith(errorMessage: 'other'), isFalse);
      expect(a == a.copyWith(startedAt: 9999), isFalse);
      expect(a == a.copyWith(completedAt: 9999), isFalse);
    });

    test('is not equal to a different type', () {
      expect(a == Object(), isFalse);
    });
  });

  group('toString', () {
    test('includes id, batchId, unitId, status and order', () {
      final unit = makeUnit(
        id: 'a',
        batchId: 'b',
        unitId: 'u',
        processingOrder: 5,
        status: TranslationBatchUnitStatus.processing,
      );
      expect(
        unit.toString(),
        'TranslationBatchUnit(id: a, batchId: b, unitId: u, '
        'status: TranslationBatchUnitStatus.processing, order: 5)',
      );
    });
  });
}
