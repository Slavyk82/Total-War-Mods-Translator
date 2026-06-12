import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/domain/translation_batch.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';

import '../../helpers/test_database.dart';

void main() {
  late Database db;
  late TranslationBatchRepository repository;

  setUp(() async {
    db = await TestDatabase.openMigrated();
    repository = TranslationBatchRepository();
  });

  tearDown(() async {
    await TestDatabase.close(db);
  });

  group('TranslationBatchRepository', () {
    // Builds a valid batch. The schema enforces:
    //   CHECK (status IN ('pending','processing','completed','failed','cancelled'))
    //   CHECK (units_completed <= units_count)
    //   CHECK (retry_count >= 0)
    // so defaults keep units_completed <= units_count and retry_count >= 0.
    TranslationBatch createTestBatch({
      String? id,
      String? projectLanguageId,
      TranslationBatchStatus? status,
      String? providerId,
      int? batchNumber,
      int? unitsCount,
      int? unitsCompleted,
      int? startedAt,
      int? completedAt,
      String? errorMessage,
      int? retryCount,
    }) {
      return TranslationBatch(
        id: id ?? 'batch-id',
        projectLanguageId: projectLanguageId ?? 'pl-1',
        status: status ?? TranslationBatchStatus.pending,
        providerId: providerId ?? 'provider-1',
        batchNumber: batchNumber ?? 1,
        unitsCount: unitsCount ?? 10,
        unitsCompleted: unitsCompleted ?? 0,
        startedAt: startedAt,
        completedAt: completedAt,
        errorMessage: errorMessage,
        retryCount: retryCount ?? 0,
      );
    }

    group('insert', () {
      test('should insert a batch successfully', () async {
        final batch = createTestBatch();

        final result = await repository.insert(batch);

        expect(result.isOk, isTrue);
        expect(result.value, equals(batch));

        // Verify it's in the database.
        final maps =
            await db.query('translation_batches', where: 'id = ?', whereArgs: [batch.id]);
        expect(maps.length, equals(1));
        expect(maps.first['project_language_id'], equals('pl-1'));
        expect(maps.first['status'], equals('pending'));
        expect(maps.first['batch_number'], equals(1));
      });

      test('should persist all enum status values', () async {
        const statuses = [
          TranslationBatchStatus.pending,
          TranslationBatchStatus.processing,
          TranslationBatchStatus.completed,
          TranslationBatchStatus.failed,
          TranslationBatchStatus.cancelled,
        ];
        for (var i = 0; i < statuses.length; i++) {
          final batch = createTestBatch(
            id: 'status-$i',
            batchNumber: i,
            status: statuses[i],
          );
          final result = await repository.insert(batch);
          expect(result.isOk, isTrue, reason: 'status ${statuses[i]} should insert');
        }

        final all = await repository.getAll();
        expect(all.value.length, equals(statuses.length));
      });

      test('should fail when inserting duplicate ID', () async {
        final batch = createTestBatch();
        await repository.insert(batch);

        final duplicate = createTestBatch(batchNumber: 2);
        final result = await repository.insert(duplicate);

        expect(result.isErr, isTrue);
      });
    });

    group('getById', () {
      test('should return batch when found', () async {
        final batch = createTestBatch(
          startedAt: 1000,
          completedAt: 2000,
          errorMessage: 'boom',
          retryCount: 3,
          status: TranslationBatchStatus.failed,
        );
        await repository.insert(batch);

        final result = await repository.getById(batch.id);

        expect(result.isOk, isTrue);
        expect(result.value.id, equals(batch.id));
        expect(result.value.status, equals(TranslationBatchStatus.failed));
        expect(result.value.startedAt, equals(1000));
        expect(result.value.completedAt, equals(2000));
        expect(result.value.errorMessage, equals('boom'));
        expect(result.value.retryCount, equals(3));
      });

      test('should return error when batch not found', () async {
        final result = await repository.getById('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getAll', () {
      test('should return empty list when no batches exist', () async {
        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });

      test('should return all batches ordered by batch_number ASC', () async {
        await repository.insert(createTestBatch(id: 'b1', batchNumber: 3));
        await repository.insert(createTestBatch(id: 'b2', batchNumber: 1));
        await repository.insert(createTestBatch(id: 'b3', batchNumber: 2));

        final result = await repository.getAll();

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(3));
        expect(result.value[0].batchNumber, equals(1));
        expect(result.value[1].batchNumber, equals(2));
        expect(result.value[2].batchNumber, equals(3));
      });
    });

    group('update', () {
      test('should update batch successfully', () async {
        final batch = createTestBatch();
        await repository.insert(batch);

        final updated = batch.copyWith(
          status: TranslationBatchStatus.completed,
          unitsCompleted: 10,
          completedAt: 5000,
        );
        final result = await repository.update(updated);

        expect(result.isOk, isTrue);
        expect(result.value.status, equals(TranslationBatchStatus.completed));

        final getResult = await repository.getById(batch.id);
        expect(getResult.value.status, equals(TranslationBatchStatus.completed));
        expect(getResult.value.unitsCompleted, equals(10));
        expect(getResult.value.completedAt, equals(5000));
      });

      test('should return error when batch not found', () async {
        final batch = createTestBatch(id: 'non-existent');

        final result = await repository.update(batch);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('delete', () {
      test('should delete batch successfully', () async {
        final batch = createTestBatch();
        await repository.insert(batch);

        final result = await repository.delete(batch.id);

        expect(result.isOk, isTrue);

        final getResult = await repository.getById(batch.id);
        expect(getResult.isErr, isTrue);
      });

      test('should return error when batch not found', () async {
        final result = await repository.delete('non-existent-id');

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('getByProjectLanguage', () {
      test('should return only batches for the given project language', () async {
        await repository
            .insert(createTestBatch(id: 'a1', projectLanguageId: 'pl-A', batchNumber: 2));
        await repository
            .insert(createTestBatch(id: 'a2', projectLanguageId: 'pl-A', batchNumber: 1));
        await repository
            .insert(createTestBatch(id: 'b1', projectLanguageId: 'pl-B', batchNumber: 1));

        final result = await repository.getByProjectLanguage('pl-A');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        // Ordered by batch_number ASC.
        expect(result.value[0].batchNumber, equals(1));
        expect(result.value[1].batchNumber, equals(2));
        expect(
          result.value.every((b) => b.projectLanguageId == 'pl-A'),
          isTrue,
        );
      });

      test('should return empty list when no batches match project language', () async {
        await repository.insert(createTestBatch(projectLanguageId: 'pl-A'));

        final result = await repository.getByProjectLanguage('pl-missing');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('getByStatus', () {
      test('should return only batches with the given status', () async {
        await repository.insert(createTestBatch(
          id: 'p1',
          batchNumber: 1,
          status: TranslationBatchStatus.processing,
        ));
        await repository.insert(createTestBatch(
          id: 'p2',
          batchNumber: 2,
          status: TranslationBatchStatus.processing,
        ));
        await repository.insert(createTestBatch(
          id: 'c1',
          batchNumber: 3,
          status: TranslationBatchStatus.completed,
          unitsCompleted: 10,
        ));

        final result = await repository.getByStatus('processing');

        expect(result.isOk, isTrue);
        expect(result.value.length, equals(2));
        expect(
          result.value.every((b) => b.status == TranslationBatchStatus.processing),
          isTrue,
        );
        // Ordered by batch_number ASC.
        expect(result.value[0].batchNumber, equals(1));
        expect(result.value[1].batchNumber, equals(2));
      });

      test('should return empty list when no batches have the status', () async {
        await repository.insert(createTestBatch(status: TranslationBatchStatus.pending));

        final result = await repository.getByStatus('cancelled');

        expect(result.isOk, isTrue);
        expect(result.value, isEmpty);
      });
    });

    group('updateProgress', () {
      test('should update units_completed and return updated entity', () async {
        final batch = createTestBatch(unitsCount: 10, unitsCompleted: 0);
        await repository.insert(batch);

        // 5 <= units_count (10) so the CHECK is respected.
        final result = await repository.updateProgress(batch.id, 5);

        expect(result.isOk, isTrue);
        expect(result.value.unitsCompleted, equals(5));
        expect(result.value.unitsCount, equals(10));

        // Verify persisted value via raw query.
        final maps =
            await db.query('translation_batches', where: 'id = ?', whereArgs: [batch.id]);
        expect(maps.first['units_completed'], equals(5));
      });

      test('should allow units_completed equal to units_count', () async {
        final batch = createTestBatch(unitsCount: 4, unitsCompleted: 0);
        await repository.insert(batch);

        final result = await repository.updateProgress(batch.id, 4);

        expect(result.isOk, isTrue);
        expect(result.value.unitsCompleted, equals(4));
      });

      test('should return error when batch not found', () async {
        final result = await repository.updateProgress('non-existent-id', 1);

        expect(result.isErr, isTrue);
        expect(result.error.message, contains('not found'));
      });
    });

    group('cleanupOrphanedBatches', () {
      test('should report zero deleted when no batches exist', () async {
        final result = await repository.cleanupOrphanedBatches();

        expect(result.isOk, isTrue);
        expect(result.value.deleted, equals(0));
      });

      test('should delete all batches and report the count', () async {
        await repository.insert(createTestBatch(id: 'b1', batchNumber: 1));
        await repository.insert(createTestBatch(id: 'b2', batchNumber: 2));
        await repository.insert(createTestBatch(id: 'b3', batchNumber: 3));

        final result = await repository.cleanupOrphanedBatches();

        expect(result.isOk, isTrue);
        expect(result.value.deleted, equals(3));

        // Verify the table is empty afterwards.
        final remaining = await repository.getAll();
        expect(remaining.value, isEmpty);

        final maps = await db.query('translation_batches');
        expect(maps, isEmpty);
      });
    });
  });
}
