import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_batch_unit.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationBatchUnitRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = TranslationBatchUnitRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('TranslationBatchUnitRepository', () {
    TranslationBatchUnit createUnit({
      String? id,
      String? batchId,
      String? unitId,
      int? processingOrder,
      TranslationBatchUnitStatus? status,
      String? errorMessage,
      int? startedAt,
      int? completedAt,
    }) {
      return TranslationBatchUnit(
        id: id ?? 'tbu-id',
        batchId: batchId ?? 'batch-1',
        unitId: unitId ?? 'unit-1',
        processingOrder: processingOrder ?? 0,
        status: status ?? TranslationBatchUnitStatus.pending,
        errorMessage: errorMessage,
        startedAt: startedAt,
        completedAt: completedAt,
      );
    }

    group('insert', () {
      test('should insert a batch unit successfully', () async {
        final unit = createUnit();

        final result = await repository.insert(unit);

        expect(result.isOk, isTrue);
        expect(result.value, equals(unit));

        final maps =
            await db.query('translation_batch_units', where: 'id = ?', whereArgs: [unit.id]);
        expect(maps.length, equals(1));
        expect(maps.first['batch_id'], equals('batch-1'));
        expect(maps.first['unit_id'], equals('unit-1'));
        expect(maps.first['status'], equals('pending'));
      });

      test('should persist all fields including optional ones', () async {
        final unit = createUnit(
          id: 'tbu-full',
          status: TranslationBatchUnitStatus.failed,
          errorMessage: 'boom',
          startedAt: 1000,
          completedAt: 2000,
        );

        final result = await repository.insert(unit);
        expect(result.isOk, isTrue);

        final maps = await db
            .query('translation_batch_units', where: 'id = ?', whereArgs: ['tbu-full']);
        expect(maps.first['status'], equals('failed'));
        expect(maps.first['error_message'], equals('boom'));
        expect(maps.first['started_at'], equals(1000));
        expect(maps.first['completed_at'], equals(2000));
      });

      test('should fail when inserting duplicate ID', () async {
        final unit = createUnit();
        await repository.insert(unit);

        final duplicate = createUnit(unitId: 'unit-2');
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });

      test('should fail when inserting duplicate (batch_id, unit_id) pair', () async {
        await repository.insert(createUnit(id: 'a', batchId: 'b1', unitId: 'u1'));

        final result =
            await repository.insert(createUnit(id: 'b', batchId: 'b1', unitId: 'u1'));

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return unit when found', () async {
        final unit = createUnit();
        await repository.insert(unit);

        final result = await repository.getById(unit.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(unit.id));
        expect(result.value.batchId, equals('batch-1'));
      });

      test('should return error when unit not found', () async {
        final result = await repository.getById('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no units exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all units ordered by processing_order ASC', () async {
        await repository.insert(createUnit(id: 'c', unitId: 'u3', processingOrder: 2));
        await repository.insert(createUnit(id: 'a', unitId: 'u1', processingOrder: 0));
        await repository.insert(createUnit(id: 'b', unitId: 'u2', processingOrder: 1));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].processingOrder, equals(0));
        expect(result.value[1].processingOrder, equals(1));
        expect(result.value[2].processingOrder, equals(2));
      });
    });

    group('update', () {
      test('should update unit successfully', () async {
        final unit = createUnit();
        await repository.insert(unit);

        final updated = unit.copyWith(
          status: TranslationBatchUnitStatus.completed,
          completedAt: 5000,
        );
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.status, equals(TranslationBatchUnitStatus.completed));

        final getResult = await repository.getById(unit.id);
        expect(getResult.value.status, equals(TranslationBatchUnitStatus.completed));
        expect(getResult.value.completedAt, equals(5000));
      });

      test('should return error when unit not found', () async {
        final unit = createUnit(id: 'non-existent');

        final result = await repository.update(unit);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete unit successfully', () async {
        final unit = createUnit();
        await repository.insert(unit);

        final result = await repository.delete(unit.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(unit.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when unit not found', () async {
        final result = await repository.delete('non-existent');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('findByBatchId', () {
      test('should return only units for the given batch, ordered', () async {
        await repository.insert(createUnit(
            id: 'a', batchId: 'b1', unitId: 'u1', processingOrder: 1));
        await repository.insert(createUnit(
            id: 'b', batchId: 'b1', unitId: 'u2', processingOrder: 0));
        await repository.insert(createUnit(
            id: 'c', batchId: 'b2', unitId: 'u3', processingOrder: 0));

        final result = await repository.findByBatchId('b1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].processingOrder, equals(0));
        expect(result.value[1].processingOrder, equals(1));
        expect(result.value.every((u) => u.batchId == 'b1'), isTrue);
      });

      test('should return empty list when batch has no units', () async {
        final result = await repository.findByBatchId('unknown-batch');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('findByBatchAndUnit', () {
      test('should return the matching unit', () async {
        await repository.insert(createUnit(id: 'a', batchId: 'b1', unitId: 'u1'));
        await repository.insert(createUnit(id: 'b', batchId: 'b1', unitId: 'u2'));

        final result = await repository.findByBatchAndUnit('b1', 'u2');

        expect(result.isOk, isTrue);
        expect(result.value, isNotNull);
        expect(result.value!.id, equals('b'));
      });

      test('should return null when no match found', () async {
        await repository.insert(createUnit(id: 'a', batchId: 'b1', unitId: 'u1'));

        final result = await repository.findByBatchAndUnit('b1', 'missing');

        expect(result.isOk, isTrue);
        expect(result.value, isNull);
      });
    });

    group('findByStatus', () {
      test('should return only units with the given status, ordered', () async {
        await repository.insert(createUnit(
            id: 'a',
            unitId: 'u1',
            processingOrder: 1,
            status: TranslationBatchUnitStatus.processing));
        await repository.insert(createUnit(
            id: 'b',
            unitId: 'u2',
            processingOrder: 0,
            status: TranslationBatchUnitStatus.processing));
        await repository.insert(createUnit(
            id: 'c',
            unitId: 'u3',
            status: TranslationBatchUnitStatus.completed));

        final result = await repository.findByStatus(
            TranslationBatchUnitStatus.processing);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('b'));
        expect(result.value[1].id, equals('a'));
      });

      test('should return empty list when no unit matches status', () async {
        await repository.insert(createUnit(status: TranslationBatchUnitStatus.pending));

        final result =
            await repository.findByStatus(TranslationBatchUnitStatus.failed);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('findByUnitId', () {
      test('should return all batch units for a translation unit, ordered', () async {
        await repository.insert(createUnit(
            id: 'a', batchId: 'b1', unitId: 'shared', processingOrder: 1));
        await repository.insert(createUnit(
            id: 'b', batchId: 'b2', unitId: 'shared', processingOrder: 0));
        await repository.insert(createUnit(
            id: 'c', batchId: 'b1', unitId: 'other', processingOrder: 0));

        final result = await repository.findByUnitId('shared');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('b'));
        expect(result.value[1].id, equals('a'));
      });

      test('should return empty list when unit id has no rows', () async {
        final result = await repository.findByUnitId('nobody');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('findByBatchIdAndStatus', () {
      test('should filter by both batch and status, ordered', () async {
        await repository.insert(createUnit(
            id: 'a',
            batchId: 'b1',
            unitId: 'u1',
            processingOrder: 1,
            status: TranslationBatchUnitStatus.pending));
        await repository.insert(createUnit(
            id: 'b',
            batchId: 'b1',
            unitId: 'u2',
            processingOrder: 0,
            status: TranslationBatchUnitStatus.pending));
        await repository.insert(createUnit(
            id: 'c',
            batchId: 'b1',
            unitId: 'u3',
            status: TranslationBatchUnitStatus.completed));
        await repository.insert(createUnit(
            id: 'd',
            batchId: 'b2',
            unitId: 'u4',
            status: TranslationBatchUnitStatus.pending));

        final result = await repository.findByBatchIdAndStatus(
            'b1', TranslationBatchUnitStatus.pending);

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(result.value[0].id, equals('b'));
        expect(result.value[1].id, equals('a'));
      });

      test('should return empty list when no rows match', () async {
        await repository.insert(createUnit(
            batchId: 'b1', status: TranslationBatchUnitStatus.completed));

        final result = await repository.findByBatchIdAndStatus(
            'b1', TranslationBatchUnitStatus.failed);

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('findPendingByBatch', () {
      test('should return only pending units for the batch', () async {
        await repository.insert(createUnit(
            id: 'a',
            batchId: 'b1',
            unitId: 'u1',
            status: TranslationBatchUnitStatus.pending));
        await repository.insert(createUnit(
            id: 'b',
            batchId: 'b1',
            unitId: 'u2',
            status: TranslationBatchUnitStatus.processing));
        await repository.insert(createUnit(
            id: 'c',
            batchId: 'b2',
            unitId: 'u3',
            status: TranslationBatchUnitStatus.pending));

        final result = await repository.findPendingByBatch('b1');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(1));
        expect(result.value.first.id, equals('a'));
      });

      test('should return empty list when batch has no pending units', () async {
        await repository.insert(createUnit(
            batchId: 'b1', status: TranslationBatchUnitStatus.completed));

        final result = await repository.findPendingByBatch('b1');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('insertBatch', () {
      test('should insert all units in one transaction and return count', () async {
        final units = [
          createUnit(id: 'a', unitId: 'u1', processingOrder: 0),
          createUnit(id: 'b', unitId: 'u2', processingOrder: 1),
          createUnit(id: 'c', unitId: 'u3', processingOrder: 2),
        ];

        final result = await repository.insertBatch(units);

        expect(result.isOk, isTrue);
        expect(result.value, equals(3));

        final maps = await db.query('translation_batch_units');
        expect(maps.length, equals(3));
      });

      test('should return 0 for empty list without touching the db', () async {
        final result = await repository.insertBatch([]);

        expect(result.isOk, isTrue);
        expect(result.value, equals(0));

        final maps = await db.query('translation_batch_units');
        expect(maps, isEmpty);
      });

      test('should fail and roll back when a unit violates a constraint', () async {
        final units = [
          createUnit(id: 'a', unitId: 'u1'),
          createUnit(id: 'a', unitId: 'u2'), // duplicate primary key id
        ];

        final result = await repository.insertBatch(units);

        expect(result.isErr, isTrue);

        // Transaction should have rolled back the first insert too.
        final maps = await db.query('translation_batch_units');
        expect(maps, isEmpty);
      });
    });
  });
}
