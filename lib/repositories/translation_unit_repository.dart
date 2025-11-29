import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_unit.dart';
import 'base_repository.dart';

/// Repository for managing TranslationUnit entities.
///
/// Provides CRUD operations and custom queries for translation units,
/// including filtering by project, key, and obsolete status.
class TranslationUnitRepository extends BaseRepository<TranslationUnit> {
  @override
  String get tableName => 'translation_units';

  @override
  TranslationUnit fromMap(Map<String, dynamic> map) {
    return TranslationUnit.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationUnit entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationUnit, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Translation unit not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationUnit>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationUnit, TWMTDatabaseException>> insert(
      TranslationUnit entity) async {
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
  Future<Result<TranslationUnit, TWMTDatabaseException>> update(
      TranslationUnit entity) async {
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
            'Translation unit not found for update: ${entity.id}');
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
            'Translation unit not found for deletion: $id');
      }
    });
  }

  /// Get all translation units for a specific project.
  ///
  /// Returns [Ok] with list of translation units, ordered by key.
  Future<Result<List<TranslationUnit>, TWMTDatabaseException>> getByProject(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ?',
        whereArgs: [projectId],
        orderBy: 'key ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get a translation unit by project ID and key.
  ///
  /// Returns [Ok] with the unit if found, [Err] with exception if not found.
  Future<Result<TranslationUnit, TWMTDatabaseException>> getByKey(
      String projectId, String key) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? AND key = ?',
        whereArgs: [projectId, key],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation unit not found for project: $projectId with key: $key');
      }

      return fromMap(maps.first);
    });
  }

  /// Mark a translation unit as obsolete.
  ///
  /// Returns [Ok] with the updated entity, [Err] with exception if update fails.
  Future<Result<TranslationUnit, TWMTDatabaseException>> markObsolete(
      String id) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final rowsAffected = await database.update(
        tableName,
        {
          'is_obsolete': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Translation unit not found for obsolete marking: $id');
      }

      // Retrieve and return the updated entity
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Translation unit not found after update: $id');
      }

      return fromMap(maps.first);
    });
  }

  /// Get all active (non-obsolete) translation units for a project.
  ///
  /// Returns [Ok] with list of active translation units, ordered by key.
  Future<Result<List<TranslationUnit>, TWMTDatabaseException>> getActive(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? AND is_obsolete = ?',
        whereArgs: [projectId, 0],
        orderBy: 'key ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get multiple translation units by their IDs in a single query.
  ///
  /// This method uses SQL IN clause for batch fetching, avoiding N+1 query problems.
  /// Instead of making N queries for N units, this makes 1 query.
  ///
  /// Performance: O(1) database query vs O(N) with individual getById calls.
  ///
  /// [ids] - List of translation unit IDs to fetch
  ///
  /// Returns [Ok] with list of translation units found (may be fewer than requested
  /// if some IDs don't exist). Units are returned in arbitrary order.
  Future<Result<List<TranslationUnit>, TWMTDatabaseException>> getByIds(
      List<String> ids) async {
    return executeQuery(() async {
      if (ids.isEmpty) {
        return <TranslationUnit>[];
      }

      // Build parameterized query with IN clause
      // Example: WHERE id IN (?, ?, ?)
      final placeholders = List.filled(ids.length, '?').join(', ');

      final maps = await database.query(
        tableName,
        where: 'id IN ($placeholders)',
        whereArgs: ids,
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Update source text for multiple translation units by key.
  ///
  /// Used when the source mod is updated and source texts have changed.
  /// Updates each key's source_text to the new value provided in the map.
  ///
  /// [projectId] - The project containing the units
  /// [sourceTextUpdates] - Map of key -> new source text
  ///
  /// Returns the count of affected rows.
  Future<Result<int, TWMTDatabaseException>> updateSourceTexts({
    required String projectId,
    required Map<String, String> sourceTextUpdates,
  }) async {
    if (sourceTextUpdates.isEmpty) {
      return Ok(0);
    }

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int totalAffected = 0;

      // Update each unit's source text
      for (final entry in sourceTextUpdates.entries) {
        final rowsAffected = await txn.rawUpdate(
          '''
          UPDATE $tableName
          SET source_text = ?,
              updated_at = ?
          WHERE project_id = ? AND key = ?
          ''',
          [entry.value, now, projectId, entry.key],
        );
        totalAffected += rowsAffected;
      }

      return totalAffected;
    });
  }
}
