import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_unit.dart';
import 'base_repository.dart';

/// Callback for reporting batch operation progress.
/// [processed] is the number of items processed so far.
/// [total] is the total number of items to process.
typedef BatchProgressCallback = void Function(int processed, int total);

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

  /// Get all obsolete translation units for a project.
  ///
  /// Returns [Ok] with list of obsolete translation units, ordered by key.
  Future<Result<List<TranslationUnit>, TWMTDatabaseException>> getObsolete(
      String projectId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_id = ? AND is_obsolete = ?',
        whereArgs: [projectId, 1],
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

  /// Reactivate multiple obsolete translation units by their keys.
  ///
  /// Used when units that were previously marked obsolete reappear in a mod update.
  /// Also updates the source text to the new value.
  ///
  /// Note: Each unit may have different source text, so we use CASE/WHEN for batch updates.
  ///
  /// [projectId] - The project containing the units
  /// [sourceTextUpdates] - Map of key -> new source text for reactivated units
  /// [onProgress] - Optional callback for progress reporting
  ///
  /// Returns the count of units reactivated.
  Future<Result<int, TWMTDatabaseException>> reactivateByKeys({
    required String projectId,
    required Map<String, String> sourceTextUpdates,
    BatchProgressCallback? onProgress,
  }) async {
    if (sourceTextUpdates.isEmpty) {
      return Ok(0);
    }

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final keys = sourceTextUpdates.keys.toList();
      int totalAffected = 0;

      // SQLite has a limit on number of parameters (default 999)
      // Each entry uses 2 params in CASE + 1 in IN clause
      // Process in batches of 200 to stay well under the limit
      const batchSize = 200;
      final total = keys.length;

      for (var i = 0; i < keys.length; i += batchSize) {
        final batchKeys = keys.skip(i).take(batchSize).toList();

        // Build CASE WHEN clause for source_text updates
        final caseBuilder = StringBuffer('CASE key ');
        final params = <Object>[];

        for (final key in batchKeys) {
          caseBuilder.write('WHEN ? THEN ? ');
          params.add(key);
          params.add(sourceTextUpdates[key]!);
        }
        caseBuilder.write('END');

        final placeholders = List.filled(batchKeys.length, '?').join(',');

        final rowsAffected = await txn.rawUpdate(
          '''
          UPDATE $tableName
          SET is_obsolete = 0,
              source_text = $caseBuilder,
              updated_at = ?
          WHERE project_id = ? AND key IN ($placeholders) AND is_obsolete = 1
          ''',
          [...params, now, projectId, ...batchKeys],
        );
        totalAffected += rowsAffected;

        // Report progress after each batch
        if (onProgress != null) {
          final processed = (i + batchKeys.length).clamp(0, total);
          onProgress(processed, total);
        }
      }

      return totalAffected;
    });
  }

  /// Mark multiple translation units as obsolete by their keys.
  ///
  /// Uses a single SQL UPDATE with IN clause for performance.
  /// For large lists, batches the operation to avoid SQL parameter limits.
  ///
  /// [projectId] - The project containing the units
  /// [keys] - List of unit keys to mark as obsolete
  /// [onProgress] - Optional callback for progress reporting
  ///
  /// Returns the count of units marked obsolete.
  Future<Result<int, TWMTDatabaseException>> markObsoleteByKeys({
    required String projectId,
    required List<String> keys,
    void Function(int processed, int total)? onProgress,
  }) async {
    if (keys.isEmpty) {
      return Ok(0);
    }

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int totalAffected = 0;

      // SQLite has a limit on number of parameters (default 999)
      // Process in batches of 500 to stay well under the limit
      const batchSize = 500;
      final total = keys.length;

      for (var i = 0; i < keys.length; i += batchSize) {
        final batch = keys.skip(i).take(batchSize).toList();
        final placeholders = List.filled(batch.length, '?').join(',');

        final rowsAffected = await txn.rawUpdate(
          '''
          UPDATE $tableName
          SET is_obsolete = 1,
              updated_at = ?
          WHERE project_id = ? AND key IN ($placeholders) AND is_obsolete = 0
          ''',
          [now, projectId, ...batch],
        );
        totalAffected += rowsAffected;

        // Report progress after each batch
        if (onProgress != null) {
          final processed = (i + batch.length).clamp(0, total);
          onProgress(processed, total);
        }
      }

      return totalAffected;
    });
  }

  /// Update source text for multiple translation units by key.
  ///
  /// Uses CASE/WHEN for batch updates to improve performance.
  ///
  /// [projectId] - The project containing the units
  /// [sourceTextUpdates] - Map of key -> new source text
  /// [onProgress] - Optional callback for progress reporting
  ///
  /// Returns the count of affected rows.
  Future<Result<int, TWMTDatabaseException>> updateSourceTexts({
    required String projectId,
    required Map<String, String> sourceTextUpdates,
    BatchProgressCallback? onProgress,
  }) async {
    if (sourceTextUpdates.isEmpty) {
      return Ok(0);
    }

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final keys = sourceTextUpdates.keys.toList();
      int totalAffected = 0;

      // SQLite has a limit on number of parameters (default 999)
      // Each entry uses 2 params in CASE + 1 in IN clause
      // Process in batches of 200 to stay well under the limit
      const batchSize = 200;
      final total = keys.length;

      for (var i = 0; i < keys.length; i += batchSize) {
        final batchKeys = keys.skip(i).take(batchSize).toList();

        // Build CASE WHEN clause for source_text updates
        final caseBuilder = StringBuffer('CASE key ');
        final params = <Object>[];

        for (final key in batchKeys) {
          caseBuilder.write('WHEN ? THEN ? ');
          params.add(key);
          params.add(sourceTextUpdates[key]!);
        }
        caseBuilder.write('END');

        final placeholders = List.filled(batchKeys.length, '?').join(',');

        final rowsAffected = await txn.rawUpdate(
          '''
          UPDATE $tableName
          SET source_text = $caseBuilder,
              updated_at = ?
          WHERE project_id = ? AND key IN ($placeholders)
          ''',
          [...params, now, projectId, ...batchKeys],
        );
        totalAffected += rowsAffected;

        // Report progress after each batch
        if (onProgress != null) {
          final processed = (i + batchKeys.length).clamp(0, total);
          onProgress(processed, total);
        }
      }

      return totalAffected;
    });
  }

  /// Get translation rows (units joined with versions) in a single SQL query.
  ///
  /// Performance optimization: Uses SQL INNER JOIN to avoid N+1 query problem.
  /// Instead of separate queries for units and versions followed by in-memory join,
  /// this fetches all data in a single database round-trip.
  ///
  /// Complexity: O(1) database query vs O(2) queries + O(n) Map operations.
  /// For 10,000+ rows, this eliminates thousands of Map insertions and lookups.
  ///
  /// [projectId] - The project containing the translation units
  /// [projectLanguageId] - The project language for the translation versions
  ///
  /// Returns a list of maps containing joined unit and version data.
  /// Each map contains all columns from both tables with version columns prefixed.
  Future<Result<List<Map<String, dynamic>>, TWMTDatabaseException>>
      getTranslationRowsJoined({
    required String projectId,
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.rawQuery(
        '''
        SELECT
          tu.id,
          tu.project_id,
          tu.key,
          tu.source_text,
          tu.context,
          tu.notes,
          tu.source_loc_file,
          tu.is_obsolete,
          tu.created_at,
          tu.updated_at,
          tv.id AS version_id,
          tv.unit_id,
          tv.project_language_id,
          tv.translated_text,
          tv.is_manually_edited,
          tv.status,
          tv.translation_source,
          tv.validation_issues,
          tv.created_at AS version_created_at,
          tv.updated_at AS version_updated_at
        FROM translation_units tu
        INNER JOIN translation_versions tv ON tu.id = tv.unit_id
        WHERE tu.project_id = ?
          AND tv.project_language_id = ?
          AND tu.is_obsolete = 0
        ORDER BY tu.key ASC
        ''',
        [projectId, projectLanguageId],
      );

      return maps;
    });
  }
}
