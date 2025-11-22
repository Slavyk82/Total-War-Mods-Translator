import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/mod_version.dart';
import 'base_repository.dart';

/// Repository for managing ModVersion entities.
///
/// Provides CRUD operations and custom queries for mod versions,
/// including filtering by project and managing current version status.
class ModVersionRepository extends BaseRepository<ModVersion> {
  @override
  String get tableName => 'mod_versions';

  @override
  ModVersion fromMap(Map<String, dynamic> map) {
    return ModVersion.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(ModVersion entity) {
    return entity.toJson();
  }

  @override
  Future<Result<ModVersion, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Mod version not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<ModVersion>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'detected_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<ModVersion, TWMTDatabaseException>> insert(
      ModVersion entity) async {
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
  Future<Result<ModVersion, TWMTDatabaseException>> update(
      ModVersion entity) async {
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
            'Mod version not found for update: ${entity.id}');
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
        throw TWMTDatabaseException('Mod version not found for deletion: $id');
      }
    });
  }

  /// Get all mod versions for a specific project.
  ///
  /// Returns [Ok] with list of versions, ordered by detection date (newest first).
  Future<Result<List<ModVersion>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'detected_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get the current version for a specific project.
  ///
  /// Returns [Ok] with the current version if found, [Err] with exception if not found.
  Future<Result<ModVersion, TWMTDatabaseException>> getCurrent(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? AND is_current = ?',
        whereArgs: [projectId, 1],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Current mod version not found for project: $projectId');
      }

      return fromMap(maps.first);
    });
  }

  /// Mark a specific version as the current version for a project.
  ///
  /// This method uses a transaction to ensure that only one version
  /// is marked as current for a project at any time.
  ///
  /// Returns [Ok] with the updated version, [Err] with exception if update fails.
  Future<Result<ModVersion, TWMTDatabaseException>> markAsCurrent(
      String versionId) async {
    return executeTransaction((txn) async {
      // First, get the version to mark as current
      final versionMaps = await txn.query(
        tableName,
        where: 'id = ?',
        whereArgs: [versionId],
        limit: 1,
      );

      if (versionMaps.isEmpty) {
        throw TWMTDatabaseException('Mod version not found: $versionId');
      }

      final version = fromMap(versionMaps.first);

      // Unmark all other versions for this project
      await txn.update(
        tableName,
        {'is_current': 0},
        where: 'project_id = ?',
        whereArgs: [version.projectId],
      );

      // Mark the specified version as current
      await txn.update(
        tableName,
        {'is_current': 1},
        where: 'id = ?',
        whereArgs: [versionId],
      );

      // Return the updated version
      final updatedMaps = await txn.query(
        tableName,
        where: 'id = ?',
        whereArgs: [versionId],
        limit: 1,
      );

      return fromMap(updatedMaps.first);
    });
  }
}
