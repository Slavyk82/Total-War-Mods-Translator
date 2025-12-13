import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/project.dart';
import 'base_repository.dart';
import '../services/projects/project_deletion_service.dart';

/// Repository for managing Project entities.
///
/// Provides CRUD operations and custom queries for projects,
/// including filtering by status and game installation.
class ProjectRepository extends BaseRepository<Project> {
  final ProjectDeletionServiceV2 _deletionService = ProjectDeletionServiceV2();

  @override
  String get tableName => 'projects';

  @override
  Project fromMap(Map<String, dynamic> map) {
    return Project.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(Project entity) {
    return entity.toJson();
  }

  @override
  Future<Result<Project, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Project not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<Project>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'updated_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<Project, TWMTDatabaseException>> insert(Project entity) async {
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
  Future<Result<Project, TWMTDatabaseException>> update(Project entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('Project not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    // Use optimized deletion service for better performance
    // Especially important for large projects with many translation units
    return _deletionService.deleteProject(id);
  }

  /// Get all projects with a specific status.
  ///
  /// Returns [Ok] with list of projects matching the status, ordered by updated date.
  Future<Result<List<Project>, TWMTDatabaseException>> getByStatus(
      String status) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'status = ?',
        whereArgs: [status],
        orderBy: 'updated_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all projects for a specific game installation.
  ///
  /// Returns [Ok] with list of projects for the game, ordered by updated date.
  Future<Result<List<Project>, TWMTDatabaseException>> getByGameInstallation(
      String gameInstallationId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'game_installation_id = ?',
        whereArgs: [gameInstallationId],
        orderBy: 'updated_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Set the mod update impact flag for a project.
  ///
  /// This flag indicates the project was impacted by a mod update,
  /// helping users identify projects that need review.
  Future<Result<void, TWMTDatabaseException>> setModUpdateImpact(
      String projectId, bool hasImpact) async {
    return executeQuery(() async {
      final rowsAffected = await database.update(
        tableName,
        {'has_mod_update_impact': hasImpact ? 1 : 0},
        where: 'id = ?',
        whereArgs: [projectId],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Project not found for update: $projectId');
      }
    });
  }

  /// Clear the mod update impact flag for a project.
  ///
  /// Convenience method to reset the flag after user acknowledges/reviews the changes.
  Future<Result<void, TWMTDatabaseException>> clearModUpdateImpact(
      String projectId) async {
    return setModUpdateImpact(projectId, false);
  }

  /// Count projects with mod update impact flag set for a game installation.
  Future<Result<int, TWMTDatabaseException>> countWithModUpdateImpact(
      String gameInstallationId) async {
    return executeQuery(() async {
      final result = await database.rawQuery('''
        SELECT COUNT(*) as cnt FROM $tableName
        WHERE game_installation_id = ? AND has_mod_update_impact = 1
      ''', [gameInstallationId]);
      return result.first['cnt'] as int;
    });
  }
}
