import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_scan_cache.dart';
import 'package:twmt/repositories/base_repository.dart';

/// Repository for managing ModScanCache entities
///
/// Provides CRUD operations for caching RPFM pack file scan results
class ModScanCacheRepository extends BaseRepository<ModScanCache> {
  @override
  String get tableName => 'mod_scan_cache';

  @override
  ModScanCache fromMap(Map<String, dynamic> map) {
    return ModScanCache.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(ModScanCache entity) {
    return entity.toJson();
  }

  @override
  Future<Result<ModScanCache, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Mod scan cache not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  /// Get cache entry by pack file path
  Future<Result<ModScanCache?, TWMTDatabaseException>> getByPackFilePath(
      String packFilePath) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'pack_file_path = ?',
        whereArgs: [packFilePath],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Get multiple cache entries by pack file paths
  Future<Result<Map<String, ModScanCache>, TWMTDatabaseException>>
      getByPackFilePaths(List<String> packFilePaths) async {
    return executeQuery(() async {
      if (packFilePaths.isEmpty) {
        return {};
      }

      final placeholders = List.filled(packFilePaths.length, '?').join(',');
      final maps = await database.query(
        tableName,
        where: 'pack_file_path IN ($placeholders)',
        whereArgs: packFilePaths,
      );

      final result = <String, ModScanCache>{};
      for (final map in maps) {
        final cache = fromMap(map);
        result[cache.packFilePath] = cache;
      }
      return result;
    });
  }

  @override
  Future<Result<List<ModScanCache>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'scanned_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<ModScanCache, TWMTDatabaseException>> insert(
      ModScanCache entity) async {
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

  /// Insert or update cache entry (upsert)
  Future<Result<ModScanCache, TWMTDatabaseException>> upsert(
      ModScanCache entity) async {
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

  /// Batch upsert multiple cache entries
  Future<Result<List<ModScanCache>, TWMTDatabaseException>> upsertBatch(
      List<ModScanCache> entities) async {
    return executeQuery(() async {
      final batch = database.batch();

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
  Future<Result<ModScanCache, TWMTDatabaseException>> update(
      ModScanCache entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final updated = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (updated == 0) {
        throw TWMTDatabaseException('Mod scan cache not found: ${entity.id}');
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
        throw TWMTDatabaseException('Mod scan cache not found: $id');
      }
    });
  }

  /// Delete cache entry by pack file path
  Future<Result<void, TWMTDatabaseException>> deleteByPackFilePath(
      String packFilePath) async {
    return executeQuery(() async {
      await database.delete(
        tableName,
        where: 'pack_file_path = ?',
        whereArgs: [packFilePath],
      );
    });
  }

  /// Delete old cache entries (older than threshold)
  Future<Result<int, TWMTDatabaseException>> deleteOlderThan(
      int thresholdSeconds) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final threshold = now - thresholdSeconds;

      return await database.delete(
        tableName,
        where: 'scanned_at < ?',
        whereArgs: [threshold],
      );
    });
  }

  /// Delete cache entries for pack files that no longer exist
  Future<Result<int, TWMTDatabaseException>> deleteOrphaned(
      List<String> existingPackFilePaths) async {
    return executeQuery(() async {
      if (existingPackFilePaths.isEmpty) {
        // Delete all entries if no paths provided
        return await database.delete(tableName);
      }

      final placeholders =
          List.filled(existingPackFilePaths.length, '?').join(',');
      return await database.delete(
        tableName,
        where: 'pack_file_path NOT IN ($placeholders)',
        whereArgs: existingPackFilePaths,
      );
    });
  }
}

