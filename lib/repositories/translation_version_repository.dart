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
  /// Returns [Ok] with list of translation version IDs where translated_text is null or empty,
  /// ordered by the translation unit key.
  Future<Result<List<String>, TWMTDatabaseException>> getUntranslatedIds({
    required String projectLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.rawQuery(
        '''
        SELECT tv.id
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
      final result = await database.rawQuery(
        '''
        SELECT
          COUNT(DISTINCT CASE
            WHEN tv.translated_text IS NOT NULL AND tv.translated_text != ''
            THEN tv.unit_id
          END) as translated_count,
          COUNT(DISTINCT CASE
            WHEN tv.status = 'pending'
            THEN tv.unit_id
          END) as pending_count,
          COUNT(DISTINCT CASE
            WHEN tv.status IN ('approved', 'reviewed')
            THEN tv.unit_id
          END) as validated_count,
          COUNT(DISTINCT CASE
            WHEN tv.status = 'error'
            THEN tv.unit_id
          END) as error_count
        FROM translation_versions tv
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
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
}
