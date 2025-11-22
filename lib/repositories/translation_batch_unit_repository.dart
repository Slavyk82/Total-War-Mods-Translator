import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_batch_unit.dart';
import 'base_repository.dart';

/// Repository for managing TranslationBatchUnit entities.
///
/// Provides CRUD operations and custom queries for translation batch units,
/// including finding units by batch ID and tracking batch unit status.
class TranslationBatchUnitRepository
    extends BaseRepository<TranslationBatchUnit> {
  @override
  String get tableName => 'translation_batch_units';

  @override
  TranslationBatchUnit fromMap(Map<String, dynamic> map) {
    return TranslationBatchUnit.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationBatchUnit entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationBatchUnit, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation batch unit not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationBatchUnit>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'processing_order ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationBatchUnit, TWMTDatabaseException>> insert(
      TranslationBatchUnit entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      await database.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return entity;
    });
  }

  @override
  Future<Result<TranslationBatchUnit, TWMTDatabaseException>> update(
      TranslationBatchUnit entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Translation batch unit not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Translation batch unit not found for deletion: $id');
      }
    });
  }

  /// Get all batch units for a specific batch.
  ///
  /// Returns [Ok] with list of batch units, ordered by processing order.
  Future<Result<List<TranslationBatchUnit>, TWMTDatabaseException>>
      findByBatchId(String batchId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'batch_id = ?',
        whereArgs: [batchId],
        orderBy: 'processing_order ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get a batch unit by batch ID and unit ID.
  ///
  /// Returns [Ok] with the batch unit if found.
  Future<Result<TranslationBatchUnit?, TWMTDatabaseException>>
      findByBatchAndUnit(String batchId, String unitId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'batch_id = ? AND unit_id = ?',
        whereArgs: [batchId, unitId],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Get all batch units with a specific status.
  ///
  /// Returns [Ok] with list of batch units matching the status.
  Future<Result<List<TranslationBatchUnit>, TWMTDatabaseException>>
      findByStatus(TranslationBatchUnitStatus status) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'status = ?',
        whereArgs: [status.name],
        orderBy: 'processing_order ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all units for a specific translation unit across all batches.
  ///
  /// Returns [Ok] with list of batch units for this translation unit.
  Future<Result<List<TranslationBatchUnit>, TWMTDatabaseException>>
      findByUnitId(String unitId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'unit_id = ?',
        whereArgs: [unitId],
        orderBy: 'processing_order ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get pending batch units for a specific batch.
  ///
  /// Returns [Ok] with list of pending batch units.
  Future<Result<List<TranslationBatchUnit>, TWMTDatabaseException>>
      findPendingByBatch(String batchId) async {
    return findByBatchIdAndStatus(
        batchId, TranslationBatchUnitStatus.pending);
  }

  /// Get batch units by batch ID and status.
  ///
  /// Returns [Ok] with list of batch units matching criteria.
  Future<Result<List<TranslationBatchUnit>, TWMTDatabaseException>>
      findByBatchIdAndStatus(
          String batchId, TranslationBatchUnitStatus status) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'batch_id = ? AND status = ?',
        whereArgs: [batchId, status.name],
        orderBy: 'processing_order ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }
}

