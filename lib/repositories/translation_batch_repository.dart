import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_batch.dart';
import '../services/shared/logging_service.dart';
import 'base_repository.dart';

/// Repository for managing TranslationBatch entities.
///
/// Provides CRUD operations and custom queries for translation batches,
/// including filtering by project language, status, and progress updates.
class TranslationBatchRepository extends BaseRepository<TranslationBatch> {
  @override
  String get tableName => 'translation_batches';

  @override
  TranslationBatch fromMap(Map<String, dynamic> map) {
    return TranslationBatch.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationBatch entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationBatch, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Translation batch not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationBatch>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'batch_number ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationBatch, TWMTDatabaseException>> insert(
      TranslationBatch entity) async {
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
  Future<Result<TranslationBatch, TWMTDatabaseException>> update(
      TranslationBatch entity) async {
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
            'Translation batch not found for update: ${entity.id}');
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
            'Translation batch not found for deletion: $id');
      }
    });
  }

  /// Get all translation batches for a specific project language.
  ///
  /// Returns [Ok] with list of batches, ordered by batch number.
  Future<Result<List<TranslationBatch>, TWMTDatabaseException>> getByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_language_id = ?',
        whereArgs: [projectLanguageId],
        orderBy: 'batch_number ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all translation batches with a specific status.
  ///
  /// Returns [Ok] with list of batches matching the status, ordered by batch number.
  Future<Result<List<TranslationBatch>, TWMTDatabaseException>> getByStatus(
      String status) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'status = ?',
        whereArgs: [status],
        orderBy: 'batch_number ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Update the progress for a translation batch.
  ///
  /// Returns [Ok] with the updated entity, [Err] with exception if update fails.
  Future<Result<TranslationBatch, TWMTDatabaseException>> updateProgress(
      String id, int unitsCompleted) async {
    return executeQuery(() async {
      final rowsAffected = await database.update(
        tableName,
        {
          'units_completed': unitsCompleted,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Translation batch not found for progress update: $id');
      }

      // Retrieve and return the updated entity
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Translation batch not found after update: $id');
      }

      return fromMap(maps.first);
    });
  }

  /// Clean up all translation batches at application startup
  ///
  /// This method deletes ALL existing batches and their associated units
  /// to ensure a clean state at application start.
  ///
  /// Returns [Ok] with cleanup stats, [Err] with exception if cleanup fails.
  Future<Result<({int deleted}), TWMTDatabaseException>> cleanupOrphanedBatches() async {
    return executeQuery(() async {
      // Count existing batches and units
      final batchCount = await database.rawQuery(
        'SELECT COUNT(*) as count FROM translation_batches',
      );
      final unitCount = await database.rawQuery(
        'SELECT COUNT(*) as count FROM translation_batch_units',
      );

      final totalBatches = batchCount.first['count'] as int;
      final totalUnits = unitCount.first['count'] as int;

      LoggingService.instance.debug('Found batches and units to clean up', {
        'totalBatches': totalBatches,
        'totalUnits': totalUnits,
      });

      if (totalBatches == 0 && totalUnits == 0) {
        LoggingService.instance.debug('No batches to clean up');
        return (deleted: 0);
      }

      // Delete all batch units first (due to foreign key constraint)
      final deletedUnits = await database.delete('translation_batch_units');
      LoggingService.instance.debug('Deleted batch units', {'count': deletedUnits});

      // Delete all batches
      final deletedBatches = await database.delete(tableName);
      LoggingService.instance.debug('Deleted batches', {'count': deletedBatches});
      LoggingService.instance.info('Cleaned up all translation batches', {
        'batches': deletedBatches,
        'units': deletedUnits,
      });

      return (deleted: deletedBatches);
    });
  }
}
