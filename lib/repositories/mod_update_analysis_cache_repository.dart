import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis_cache.dart';
import 'package:twmt/repositories/base_repository.dart';

/// Repository for managing ModUpdateAnalysisCache entities.
///
/// Caches mod update analysis results to avoid expensive TSV extraction
/// when the source pack file hasn't changed.
class ModUpdateAnalysisCacheRepository
    extends BaseRepository<ModUpdateAnalysisCache> {
  @override
  String get tableName => 'mod_update_analysis_cache';

  @override
  ModUpdateAnalysisCache fromMap(Map<String, dynamic> map) {
    return ModUpdateAnalysisCache.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(ModUpdateAnalysisCache entity) {
    return entity.toJson();
  }

  @override
  Future<Result<ModUpdateAnalysisCache, TWMTDatabaseException>> getById(
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
            'Mod update analysis cache not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  /// Get cache entry by project ID and pack file path.
  Future<Result<ModUpdateAnalysisCache?, TWMTDatabaseException>>
      getByProjectAndPath(String projectId, String packFilePath) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? AND pack_file_path = ?',
        whereArgs: [projectId, packFilePath],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Get all cache entries for a project.
  Future<Result<List<ModUpdateAnalysisCache>, TWMTDatabaseException>>
      getByProjectId(String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get multiple cache entries by project IDs (batch).
  Future<Result<Map<String, ModUpdateAnalysisCache>, TWMTDatabaseException>>
      getByProjectIds(List<String> projectIds) async {
    return executeQuery(() async {
      if (projectIds.isEmpty) {
        return {};
      }

      final placeholders = List.filled(projectIds.length, '?').join(',');
      final maps = await database.query(
        tableName,
        where: 'project_id IN ($placeholders)',
        whereArgs: projectIds,
      );

      final result = <String, ModUpdateAnalysisCache>{};
      for (final map in maps) {
        final cache = fromMap(map);
        result[cache.projectId] = cache;
      }
      return result;
    });
  }

  @override
  Future<Result<List<ModUpdateAnalysisCache>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'analyzed_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<ModUpdateAnalysisCache, TWMTDatabaseException>> insert(
      ModUpdateAnalysisCache entity) async {
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

  /// Insert or update cache entry (upsert).
  Future<Result<ModUpdateAnalysisCache, TWMTDatabaseException>> upsert(
      ModUpdateAnalysisCache entity) async {
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

  /// Batch upsert multiple cache entries.
  Future<Result<List<ModUpdateAnalysisCache>, TWMTDatabaseException>>
      upsertBatch(List<ModUpdateAnalysisCache> entities) async {
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
  Future<Result<ModUpdateAnalysisCache, TWMTDatabaseException>> update(
      ModUpdateAnalysisCache entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final updated = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (updated == 0) {
        throw TWMTDatabaseException(
            'Mod update analysis cache not found: ${entity.id}');
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
        throw TWMTDatabaseException(
            'Mod update analysis cache not found: $id');
      }
    });
  }

  /// Delete all cache entries for a project.
  Future<Result<void, TWMTDatabaseException>> deleteByProjectId(
      String projectId) async {
    return executeQuery(() async {
      await database.delete(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
      );
    });
  }

  /// Delete cache entries older than the specified threshold.
  Future<Result<int, TWMTDatabaseException>> deleteOlderThan(
      int thresholdSeconds) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final threshold = now - thresholdSeconds;

      return await database.delete(
        tableName,
        where: 'analyzed_at < ?',
        whereArgs: [threshold],
      );
    });
  }
}
