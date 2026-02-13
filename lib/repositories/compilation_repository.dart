import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/compilation.dart';
import 'base_repository.dart';

/// Repository for managing Compilation entities.
///
/// Provides CRUD operations and custom queries for compilations,
/// including managing the compilation-project relationships.
class CompilationRepository extends BaseRepository<Compilation> {
  @override
  String get tableName => 'compilations';

  @override
  Compilation fromMap(Map<String, dynamic> map) {
    return Compilation.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(Compilation entity) {
    return entity.toJson();
  }

  @override
  Future<Result<Compilation, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Compilation not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<Compilation>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'updated_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<Compilation, TWMTDatabaseException>> insert(
      Compilation entity) async {
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
  Future<Result<Compilation, TWMTDatabaseException>> update(
      Compilation entity) async {
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
            'Compilation not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      // CompilationProjects will be deleted via CASCADE
      await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  /// Get all compilations for a specific game installation.
  Future<Result<List<Compilation>, TWMTDatabaseException>> getByGameInstallation(
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

  /// Get project IDs for a compilation.
  Future<Result<List<String>, TWMTDatabaseException>> getProjectIds(
      String compilationId) async {
    return executeQuery(() async {
      final maps = await database.query(
        'compilation_projects',
        columns: ['project_id'],
        where: 'compilation_id = ?',
        whereArgs: [compilationId],
        orderBy: 'sort_order ASC',
      );

      return maps.map((map) => map['project_id'] as String).toList();
    });
  }

  /// Get compilation projects with full details.
  Future<Result<List<CompilationProject>, TWMTDatabaseException>>
      getCompilationProjects(String compilationId) async {
    return executeQuery(() async {
      final maps = await database.query(
        'compilation_projects',
        where: 'compilation_id = ?',
        whereArgs: [compilationId],
        orderBy: 'sort_order ASC',
      );

      return maps.map((map) => CompilationProject.fromJson(map)).toList();
    });
  }

  /// Add a project to a compilation.
  Future<Result<CompilationProject, TWMTDatabaseException>> addProject(
    String compilationId,
    String projectId,
  ) async {
    return executeQuery(() async {
      // Get the next sort order
      final maxOrderResult = await database.rawQuery('''
        SELECT COALESCE(MAX(sort_order), -1) + 1 as next_order
        FROM compilation_projects
        WHERE compilation_id = ?
      ''', [compilationId]);

      final nextOrder = (maxOrderResult.first['next_order'] as int?) ?? 0;

      final compilationProject = CompilationProject(
        id: const Uuid().v4(),
        compilationId: compilationId,
        projectId: projectId,
        sortOrder: nextOrder,
        addedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      await database.insert(
        'compilation_projects',
        compilationProject.toJson(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      // Update compilation updated_at
      await database.update(
        tableName,
        {'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
        where: 'id = ?',
        whereArgs: [compilationId],
      );

      return compilationProject;
    });
  }

  /// Remove a project from a compilation.
  Future<Result<void, TWMTDatabaseException>> removeProject(
    String compilationId,
    String projectId,
  ) async {
    return executeQuery(() async {
      await database.delete(
        'compilation_projects',
        where: 'compilation_id = ? AND project_id = ?',
        whereArgs: [compilationId, projectId],
      );

      // Update compilation updated_at
      await database.update(
        tableName,
        {'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
        where: 'id = ?',
        whereArgs: [compilationId],
      );
    });
  }

  /// Set the projects for a compilation (replaces all existing).
  Future<Result<void, TWMTDatabaseException>> setProjects(
    String compilationId,
    List<String> projectIds,
  ) async {
    return executeTransaction((txn) async {
      // Delete existing projects
      await txn.delete(
        'compilation_projects',
        where: 'compilation_id = ?',
        whereArgs: [compilationId],
      );

      // Add new projects
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      for (var i = 0; i < projectIds.length; i++) {
        final compilationProject = CompilationProject(
          id: const Uuid().v4(),
          compilationId: compilationId,
          projectId: projectIds[i],
          sortOrder: i,
          addedAt: now,
        );

        await txn.insert(
          'compilation_projects',
          compilationProject.toJson(),
        );
      }

      // Update compilation updated_at
      await txn.update(
        tableName,
        {'updated_at': now},
        where: 'id = ?',
        whereArgs: [compilationId],
      );
    });
  }

  /// Update compilation after generation.
  Future<Result<Compilation, TWMTDatabaseException>> updateAfterGeneration(
    String compilationId,
    String outputPath,
  ) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await database.update(
        tableName,
        {
          'last_output_path': outputPath,
          'last_generated_at': now,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [compilationId],
      );

      // Return updated compilation
      final result = await getById(compilationId);
      return result.unwrap();
    });
  }

  /// Update compilation after publishing to Steam Workshop.
  Future<Result<void, TWMTDatabaseException>> updateAfterPublish(
    String compilationId,
    String publishedSteamId,
    int publishedAt,
  ) async {
    return executeQuery(() async {
      final rowsAffected = await database.update(
        tableName,
        {
          'published_steam_id': publishedSteamId,
          'published_at': publishedAt,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [compilationId],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Compilation not found for publish update: $compilationId');
      }
    });
  }

  /// Get compilation count for statistics.
  Future<Result<int, TWMTDatabaseException>> getCount() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as cnt FROM $tableName',
      );
      return (result.first['cnt'] as int?) ?? 0;
    });
  }
}
