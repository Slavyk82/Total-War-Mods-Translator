import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/project_language.dart';
import 'base_repository.dart';

/// Repository for managing ProjectLanguage entities.
///
/// Provides CRUD operations and custom queries for project languages,
/// including filtering by project and updating progress.
class ProjectLanguageRepository extends BaseRepository<ProjectLanguage> {
  @override
  String get tableName => 'project_languages';

  @override
  ProjectLanguage fromMap(Map<String, dynamic> map) {
    return ProjectLanguage.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(ProjectLanguage entity) {
    return entity.toJson();
  }

  @override
  Future<Result<ProjectLanguage, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Project language not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<ProjectLanguage>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<ProjectLanguage, TWMTDatabaseException>> insert(
      ProjectLanguage entity) async {
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
  Future<Result<ProjectLanguage, TWMTDatabaseException>> update(
      ProjectLanguage entity) async {
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
            'Project language not found for update: ${entity.id}');
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
            'Project language not found for deletion: $id');
      }
    });
  }

  /// Get all project languages for a specific project.
  ///
  /// Returns [Ok] with list of project languages, ordered by creation date.
  Future<Result<List<ProjectLanguage>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'created_at ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get a project language by project and language IDs.
  ///
  /// Returns [Ok] with the project language if found, [Err] with exception if not found.
  Future<Result<ProjectLanguage, TWMTDatabaseException>> getByProjectAndLanguage(
      String projectId, String languageId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? AND language_id = ?',
        whereArgs: [projectId, languageId],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Project language not found for project: $projectId and language: $languageId');
      }

      return fromMap(maps.first);
    });
  }

  /// Update the progress percentage for a project language.
  ///
  /// Returns [Ok] with the updated entity, [Err] with exception if update fails.
  Future<Result<ProjectLanguage, TWMTDatabaseException>> updateProgress(
      String id, double progressPercent) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final rowsAffected = await database.update(
        tableName,
        {
          'progress_percent': progressPercent,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Project language not found for progress update: $id');
      }

      // Retrieve and return the updated entity
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Project language not found after update: $id');
      }

      return fromMap(maps.first);
    });
  }
}
