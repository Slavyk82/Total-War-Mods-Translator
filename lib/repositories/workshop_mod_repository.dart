import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/workshop_mod.dart';
import 'package:twmt/repositories/base_repository.dart';

/// Repository for managing WorkshopMod entities
///
/// Provides CRUD operations and queries for Steam Workshop mod metadata
class WorkshopModRepository extends BaseRepository<WorkshopMod> {
  @override
  String get tableName => 'workshop_mods';

  @override
  WorkshopMod fromMap(Map<String, dynamic> map) {
    return WorkshopMod.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(WorkshopMod entity) {
    return entity.toJson();
  }

  @override
  Future<Result<WorkshopMod, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Workshop mod not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  /// Get workshop mod by Workshop ID
  Future<Result<WorkshopMod, TWMTDatabaseException>> getByWorkshopId(
      String workshopId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'workshop_id = ?',
        whereArgs: [workshopId],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Workshop mod not found with workshop_id: $workshopId');
      }

      return fromMap(maps.first);
    });
  }

  /// Get multiple workshop mods by Workshop IDs
  Future<Result<List<WorkshopMod>, TWMTDatabaseException>>
      getByWorkshopIds(List<String> workshopIds) async {
    return executeQuery(() async {
      if (workshopIds.isEmpty) {
        return [];
      }

      final placeholders = List.filled(workshopIds.length, '?').join(',');
      final maps = await database.query(
        tableName,
        where: 'workshop_id IN ($placeholders)',
        whereArgs: workshopIds,
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<List<WorkshopMod>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'time_updated DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all workshop mods for specific app
  Future<Result<List<WorkshopMod>, TWMTDatabaseException>> getByAppId(
      int appId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'app_id = ?',
        whereArgs: [appId],
        orderBy: 'time_updated DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<WorkshopMod, TWMTDatabaseException>> insert(
      WorkshopMod entity) async {
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

  /// Insert or update workshop mod (upsert)
  Future<Result<WorkshopMod, TWMTDatabaseException>> upsert(
      WorkshopMod entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      await database.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      return entity;
    });
  }

  /// Batch upsert multiple workshop mods
  ///
  /// Uses a transaction to ensure atomicity - all inserts succeed or none do.
  Future<Result<List<WorkshopMod>, TWMTDatabaseException>> upsertBatch(
      List<WorkshopMod> entities) async {
    if (entities.isEmpty) {
      return const Ok([]);
    }

    return executeTransaction((txn) async {
      final batch = txn.batch();

      for (final entity in entities) {
        final map = toMap(entity);
        batch.insert(
          tableName,
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
      return entities;
    });
  }

  @override
  Future<Result<WorkshopMod, TWMTDatabaseException>> update(
      WorkshopMod entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final updated = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (updated == 0) {
        throw TWMTDatabaseException('Workshop mod not found: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      final deleted = await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (deleted == 0) {
        throw TWMTDatabaseException('Workshop mod not found: $id');
      }
    });
  }

  /// Delete by workshop ID
  Future<Result<void, TWMTDatabaseException>> deleteByWorkshopId(
      String workshopId) async {
    return executeQuery(() async {
      await database.delete(
        tableName,
        where: 'workshop_id = ?',
        whereArgs: [workshopId],
      );
    });
  }

  /// Check if workshop mod exists
  Future<Result<bool, TWMTDatabaseException>> existsByWorkshopId(
      String workshopId) async {
    return executeQuery(() async {
      final result = await database.query(
        tableName,
        columns: ['COUNT(*) as count'],
        where: 'workshop_id = ?',
        whereArgs: [workshopId],
      );

      final count = result.first['count'] as int;
      return count > 0;
    });
  }

  /// Update last checked timestamp
  Future<Result<void, TWMTDatabaseException>> updateLastChecked(
      String workshopId, int timestamp) async {
    return executeQuery(() async {
      await database.update(
        tableName,
        {'last_checked_at': timestamp, 'updated_at': timestamp},
        where: 'workshop_id = ?',
        whereArgs: [workshopId],
      );
    });
  }

  /// Update time_updated timestamp (called when local file is confirmed current)
  ///
  /// This syncs the cached Steam timestamp with the actual Steam API value
  /// after the user has re-downloaded the mod file.
  Future<Result<void, TWMTDatabaseException>> updateTimeUpdated(
      String workshopId, int timeUpdated) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await database.update(
        tableName,
        {'time_updated': timeUpdated, 'updated_at': now},
        where: 'workshop_id = ?',
        whereArgs: [workshopId],
      );
    });
  }

  /// Get mods that need update check (last checked > threshold)
  Future<Result<List<WorkshopMod>, TWMTDatabaseException>>
      getModsNeedingUpdateCheck(int thresholdSeconds) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final threshold = now - thresholdSeconds;

      final maps = await database.query(
        tableName,
        where: 'last_checked_at IS NULL OR last_checked_at < ?',
        whereArgs: [threshold],
        orderBy: 'last_checked_at ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Set hidden status for a mod by workshop ID
  Future<Result<void, TWMTDatabaseException>> setHidden(
      String workshopId, bool isHidden) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await database.update(
        tableName,
        {'is_hidden': isHidden ? 1 : 0, 'updated_at': now},
        where: 'workshop_id = ?',
        whereArgs: [workshopId],
      );
    });
  }

  /// Get all hidden workshop IDs
  Future<Result<Set<String>, TWMTDatabaseException>> getHiddenWorkshopIds() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        columns: ['workshop_id'],
        where: 'is_hidden = 1',
      );

      return maps.map((map) => map['workshop_id'] as String).toSet();
    });
  }
}

