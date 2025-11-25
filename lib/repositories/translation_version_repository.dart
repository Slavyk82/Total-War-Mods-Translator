import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_version.dart';
import '../models/domain/project_statistics.dart';
import 'base_repository.dart';

/// Repository for managing TranslationVersion entities.
///
/// Provides CRUD operations and custom queries for translation versions,
/// including filtering by unit, project language, and status.
class TranslationVersionRepository
    extends BaseRepository<TranslationVersion> {
  @override
  String get tableName => 'translation_versions';

  @override
  TranslationVersion fromMap(Map<String, dynamic> map) {
    return TranslationVersion.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationVersion entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationVersion, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Translation version not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationVersion, TWMTDatabaseException>> insert(
      TranslationVersion entity) async {
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

  /// Insert a translation version within an existing transaction.
  ///
  /// This method is used for batch operations where multiple inserts
  /// need to happen within a single transaction to prevent FTS5 corruption.
  ///
  /// Parameters:
  /// - [txn]: The transaction to execute the insert within
  /// - [entity]: The translation version to insert
  Future<void> insertWithTransaction(
      Transaction txn, TranslationVersion entity) async {
    final map = toMap(entity);
    await txn.insert(
      tableName,
      map,
      conflictAlgorithm: ConflictAlgorithm.abort,
    );
  }

  @override
  Future<Result<TranslationVersion, TWMTDatabaseException>> update(
      TranslationVersion entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      // Remove id from map - we cannot update PRIMARY KEY
      map.remove('id');

      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'Translation version not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  /// Upsert (INSERT or UPDATE) a single translation version.
  ///
  /// If translation exists for (unitId, projectLanguageId), UPDATE it.
  /// If not, INSERT new translation.
  ///
  /// Uses a transaction to ensure atomicity of the read-modify-write pattern,
  /// preventing race conditions and database corruption under concurrent access.
  ///
  /// Returns [Ok] with the saved entity on success.
  Future<Result<TranslationVersion, TWMTDatabaseException>> upsert(
      TranslationVersion entity) async {
    return executeTransaction((txn) async {
      // Check if translation exists (within transaction for atomicity)
      final existingMaps = await txn.query(
        tableName,
        where: 'unit_id = ? AND project_language_id = ?',
        whereArgs: [entity.unitId, entity.projectLanguageId],
        columns: ['id', 'created_at'],
        limit: 1,
      );

      if (existingMaps.isNotEmpty) {
        // UPDATE: Preserve original ID and createdAt
        final existing = existingMaps.first;
        final existingId = existing['id'] as String;
        final existingCreatedAt = existing['created_at'] as int;

        final map = toMap(entity);
        map['id'] = existingId;
        map['created_at'] = existingCreatedAt;
        map.remove('id'); // Remove from UPDATE fields

        await txn.update(
          tableName,
          map,
          where: 'id = ?',
          whereArgs: [existingId],
        );

        return entity;
      } else {
        // INSERT: Use entity's ID and timestamps
        final map = toMap(entity);
        await txn.insert(
          tableName,
          map,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        return entity;
      }
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
            'Translation version not found for deletion: $id');
      }
    });
  }

  /// Insert multiple translation versions in a single transaction.
  ///
  /// More efficient than calling insert() multiple times.
  /// Returns [Ok] with the list of inserted entities on success.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> insertBatch(
      List<TranslationVersion> entities) async {
    if (entities.isEmpty) {
      return Ok([]);
    }

    return executeQuery(() async {
      final batch = database.batch();

      for (final entity in entities) {
        final map = toMap(entity);
        batch.insert(
          tableName,
          map,
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      await batch.commit(noResult: true);
      return entities;
    });
  }

  /// Upsert (INSERT or UPDATE) multiple translation versions in a single transaction.
  ///
  /// For each entity:
  /// - If translation exists for (unitId, projectLanguageId), UPDATE it
  /// - If not, INSERT new translation
  ///
  /// This is significantly faster than individual operations as it uses:
  /// - Single transaction for atomicity (prevents corruption under concurrent access)
  /// - Batch query for existence checks
  /// - Single batch commit
  ///
  /// Returns [Ok] with the list of successfully saved entities.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> upsertBatch(
      List<TranslationVersion> entities) async {
    if (entities.isEmpty) {
      return Ok([]);
    }

    return executeTransaction((txn) async {
      // Step 1: Check which translations already exist (batch query within transaction)
      final unitIds = entities.map((e) => e.unitId).toSet().toList();
      final projectLanguageIds = entities.map((e) => e.projectLanguageId).toSet().toList();

      // Build placeholders for IN clause
      final unitPlaceholders = List.filled(unitIds.length, '?').join(',');
      final langPlaceholders = List.filled(projectLanguageIds.length, '?').join(',');

      final existingMaps = await txn.rawQuery('''
        SELECT id, unit_id, project_language_id, created_at
        FROM $tableName
        WHERE unit_id IN ($unitPlaceholders)
          AND project_language_id IN ($langPlaceholders)
      ''', [...unitIds, ...projectLanguageIds]);

      // Build lookup map: (unitId, projectLanguageId) -> (id, createdAt)
      final existingLookup = <String, ({String id, int createdAt})>{};
      for (final map in existingMaps) {
        final key = '${map['unit_id']}:${map['project_language_id']}';
        existingLookup[key] = (
          id: map['id'] as String,
          createdAt: map['created_at'] as int,
        );
      }

      // Step 2: Build batch operations within transaction
      final batch = txn.batch();

      for (final entity in entities) {
        final lookupKey = '${entity.unitId}:${entity.projectLanguageId}';
        final existing = existingLookup[lookupKey];

        if (existing != null) {
          // UPDATE: Preserve original ID and createdAt
          final map = toMap(entity);
          map['id'] = existing.id; // Keep original ID
          map['created_at'] = existing.createdAt; // Keep original createdAt
          map.remove('id'); // Remove from UPDATE fields

          batch.update(
            tableName,
            map,
            where: 'id = ?',
            whereArgs: [existing.id],
          );
        } else {
          // INSERT: Use entity's ID and timestamps
          final map = toMap(entity);
          batch.insert(
            tableName,
            map,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      // Step 3: Commit batch (within transaction for atomicity)
      await batch.commit(noResult: true);

      return entities;
    });
  }

  /// Get all translation versions for a specific unit.
  ///
  /// Returns [Ok] with list of versions, ordered by creation date.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> getByUnit(
      String unitId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'unit_id = ?',
        whereArgs: [unitId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all translation versions for a specific project language.
  ///
  /// Returns [Ok] with list of versions, ordered by creation date.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>>
      getByProjectLanguage(String projectLanguageId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'project_language_id = ?',
        whereArgs: [projectLanguageId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all translation versions with a specific status.
  ///
  /// Returns [Ok] with list of versions matching the status, ordered by creation date.
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>> getByStatus(
      String status) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'status = ?',
        whereArgs: [status],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all untranslated unit IDs for a specific project language.
  ///
  /// Returns [Ok] with list of unit IDs where translated_text is null or empty,
  /// ordered by the translation unit key.
  Future<Result<List<String>, TWMTDatabaseException>> getUntranslatedIds({
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.rawQuery(
        '''
        SELECT tu.id
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = ?
          AND (tv.translated_text IS NULL OR tv.translated_text = '')
          AND tu.is_obsolete = 0
        ORDER BY tu.key
        ''',
        [projectLanguageId],
      );

      return maps.map((map) => map['id'] as String).toList();
    });
  }

  /// Filter a list of IDs to only include untranslated ones.
  ///
  /// Returns [Ok] with list of IDs where translated_text is null or empty.
  Future<Result<List<String>, TWMTDatabaseException>> filterUntranslatedIds({
    required List<String> ids,
  }) async {
    if (ids.isEmpty) {
      return Ok([]);
    }

    return executeQuery(() async {
      // Create placeholders for IN clause
      final placeholders = List.filled(ids.length, '?').join(',');

      // BUG FIX: The ids parameter contains unit_id, not version id
      // We need to query by unit_id, not by id
      // AND we need to return unit_id, not version id
      final maps = await database.rawQuery(
        '''
        SELECT unit_id
        FROM translation_versions
        WHERE unit_id IN ($placeholders)
          AND (translated_text IS NULL OR translated_text = '')
        ''',
        ids,
      );

      return maps.map((map) => map['unit_id'] as String).toList();
    });
  }

  /// Get translation version by unit and project language.
  ///
  /// Returns [Ok] with the version if found, [Err] if not found or error occurs.
  Future<Result<TranslationVersion, TWMTDatabaseException>> getByUnitAndProjectLanguage({
    required String unitId,
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'unit_id = ? AND project_language_id = ?',
        whereArgs: [unitId, projectLanguageId],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
          'Translation version not found for unit $unitId and project language $projectLanguageId',
        );
      }

      return fromMap(maps.first);
    });
  }

  /// Count total translation versions for a project language.
  ///
  /// Returns [Ok] with count of all versions for the project language.
  Future<Result<int, TWMTDatabaseException>> countByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ?',
        [projectLanguageId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count translated versions for a project language.
  ///
  /// Returns [Ok] with count of versions that have non-empty translated text.
  Future<Result<int, TWMTDatabaseException>> countTranslatedByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ? AND translated_text IS NOT NULL AND translated_text != ?',
        [projectLanguageId, ''],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count validated versions for a project language.
  ///
  /// Returns [Ok] with count of versions with validated or approved status.
  Future<Result<int, TWMTDatabaseException>> countValidatedByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ? AND (status = ? OR status = ?)',
        [projectLanguageId, 'approved', 'reviewed'],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count versions needing review for a project language.
  ///
  /// Returns [Ok] with count of versions with needs_review status.
  Future<Result<int, TWMTDatabaseException>> countNeedsReviewByProjectLanguage(
      String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE project_language_id = ? AND status = ?',
        [projectLanguageId, 'needs_review'],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count translated versions for a project (across all languages).
  ///
  /// Returns [Ok] with count of versions that have non-empty translated text
  /// for any unit in the project.
  Future<Result<int, TWMTDatabaseException>> countTranslatedByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND tv.translated_text IS NOT NULL
          AND tv.translated_text != ''
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count pending versions for a project (across all languages).
  ///
  /// Returns [Ok] with count of units that have at least one version with pending status.
  Future<Result<int, TWMTDatabaseException>> countPendingByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND tv.status = 'pending'
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count validated versions for a project (across all languages).
  ///
  /// Returns [Ok] with count of units that have at least one version with validated/approved status.
  Future<Result<int, TWMTDatabaseException>> countValidatedByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND (tv.status = 'approved' OR tv.status = 'reviewed')
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Count error versions for a project (across all languages).
  ///
  /// Returns [Ok] with count of units that have at least one version with error status.
  Future<Result<int, TWMTDatabaseException>> countErrorByProject(
      String projectId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT COUNT(DISTINCT tv.unit_id) as count
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
          AND tv.status = 'error'
        ''',
        [projectId],
      );

      final count = result.first['count'] as int?;
      return count ?? 0;
    });
  }

  /// Get all translation statistics for a project in a single optimized query.
  ///
  /// Consolidates 4 separate COUNT queries into 1 for 3-4x performance improvement.
  ///
  /// Returns [Ok] with [ProjectStatistics] containing all counts, or [Err] on database error.
  Future<Result<ProjectStatistics, TWMTDatabaseException>>
      getProjectStatistics(String projectId) async {
    return executeQuery(() async {
      // Single query with conditional aggregation - much faster than 4 separate queries
      // Uses status-based counting consistent with editor statistics
      // Groups by unit_id and takes the "best" status per unit across all languages
      final result = await database.rawQuery(
        '''
        WITH unit_best_status AS (
          -- For each unit, get the best status across all target languages
          -- Priority: approved > reviewed > translated > needs_review > translating > pending
          SELECT
            tu.id as unit_id,
            MAX(CASE
              WHEN tv.status = 'approved' THEN 6
              WHEN tv.status = 'reviewed' THEN 5
              WHEN tv.status = 'translated' THEN 4
              WHEN tv.status = 'needs_review' THEN 3
              WHEN tv.status = 'translating' THEN 2
              WHEN tv.status = 'pending' THEN 1
              ELSE 0
            END) as status_priority,
            MAX(CASE WHEN tv.status = 'approved' THEN 1 ELSE 0 END) as is_approved,
            MAX(CASE WHEN tv.status = 'reviewed' THEN 1 ELSE 0 END) as is_reviewed,
            MAX(CASE WHEN tv.status = 'translated' THEN 1 ELSE 0 END) as is_translated,
            MAX(CASE WHEN tv.status = 'pending' OR tv.status = 'translating' THEN 1 ELSE 0 END) as is_pending,
            MAX(CASE WHEN tv.status = 'needs_review' THEN 1 ELSE 0 END) as is_needs_review
          FROM translation_units tu
          INNER JOIN translation_versions tv ON tv.unit_id = tu.id
          WHERE tu.project_id = ?
          GROUP BY tu.id
        )
        SELECT
          -- Translated: units where best status is translated (but not approved/reviewed)
          COUNT(CASE WHEN status_priority = 4 THEN 1 END) as translated_count,
          -- Pending: units where best status is pending/translating
          COUNT(CASE WHEN status_priority <= 2 THEN 1 END) as pending_count,
          -- Validated: units where best status is approved or reviewed
          COUNT(CASE WHEN status_priority >= 5 THEN 1 END) as validated_count,
          -- Needs review count (treated as error for display purposes)
          COUNT(CASE WHEN status_priority = 3 THEN 1 END) as error_count
        FROM unit_best_status
        ''',
        [projectId],
      );

      if (result.isEmpty) {
        return ProjectStatistics.empty();
      }

      final row = result.first;
      return ProjectStatistics(
        translatedCount: (row['translated_count'] as int?) ?? 0,
        pendingCount: (row['pending_count'] as int?) ?? 0,
        validatedCount: (row['validated_count'] as int?) ?? 0,
        errorCount: (row['error_count'] as int?) ?? 0,
      );
    });
  }

  /// Get translation statistics for a specific project language.
  ///
  /// Returns statistics based on status values, consistent with editor statistics.
  ///
  /// Returns [Ok] with [ProjectStatistics] containing all counts, or [Err] on database error.
  Future<Result<ProjectStatistics, TWMTDatabaseException>>
      getLanguageStatistics(String projectLanguageId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        '''
        SELECT
          COUNT(CASE WHEN tv.status = 'translated' THEN 1 END) as translated_count,
          COUNT(CASE WHEN tv.status IN ('pending', 'translating') THEN 1 END) as pending_count,
          COUNT(CASE WHEN tv.status IN ('approved', 'reviewed') THEN 1 END) as validated_count,
          COUNT(CASE WHEN tv.status = 'needs_review' THEN 1 END) as error_count
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tv.project_language_id = ?
          AND tu.is_obsolete = 0
        ''',
        [projectLanguageId],
      );

      if (result.isEmpty) {
        return ProjectStatistics.empty();
      }

      final row = result.first;
      return ProjectStatistics(
        translatedCount: (row['translated_count'] as int?) ?? 0,
        pendingCount: (row['pending_count'] as int?) ?? 0,
        validatedCount: (row['validated_count'] as int?) ?? 0,
        errorCount: (row['error_count'] as int?) ?? 0,
      );
    });
  }
}
