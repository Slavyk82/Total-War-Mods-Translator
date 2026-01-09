import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_version.dart';
import 'base_repository.dart';
import 'mixins/translation_version_batch_mixin.dart';
import 'mixins/translation_version_statistics_mixin.dart';

/// Repository for managing TranslationVersion entities.
///
/// Provides CRUD operations and custom queries for translation versions,
/// including filtering by unit, project language, and status.
///
/// Complex operations are delegated to mixins:
/// - [TranslationVersionBatchMixin]: Batch insert/upsert operations
/// - [TranslationVersionStatisticsMixin]: Statistics and counting queries
class TranslationVersionRepository extends BaseRepository<TranslationVersion>
    with TranslationVersionBatchMixin, TranslationVersionStatisticsMixin {
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
        throw TWMTDatabaseException(
            'Translation version not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationVersion>, TWMTDatabaseException>>
      getAll() async {
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

  /// Upsert (INSERT or UPDATE) a single translation version.
  ///
  /// If translation exists for (unitId, projectLanguageId), UPDATE it.
  /// If not, INSERT new translation.
  ///
  /// Uses a transaction to ensure atomicity of the read-modify-write pattern.
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

        // Create update map without ID (ID is used in WHERE clause, not updated)
        final map = toMap(entity);
        map.remove('id'); // Remove ID - it's used in WHERE clause, not updated
        map['created_at'] = existingCreatedAt; // Preserve original creation time

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

  /// Get all translation versions for a specific unit.
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
  /// Excludes units that should be skipped from translation:
  /// - Obsolete units
  /// - Units with [HIDDEN] prefix
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
          AND UPPER(TRIM(tu.source_text)) NOT LIKE '[HIDDEN]%'
        ORDER BY tu.key
        ''',
        [projectLanguageId],
      );

      return maps.map((map) => map['id'] as String).toList();
    });
  }

  /// Filter a list of IDs to only include untranslated ones.
  ///
  /// Requires [projectLanguageId] to avoid returning duplicates when
  /// the same unit has multiple translation versions (one per language).
  Future<Result<List<String>, TWMTDatabaseException>> filterUntranslatedIds({
    required List<String> ids,
    required String projectLanguageId,
  }) async {
    if (ids.isEmpty) {
      return Ok([]);
    }

    return executeQuery(() async {
      final placeholders = List.filled(ids.length, '?').join(',');

      final maps = await database.rawQuery(
        '''
        SELECT unit_id
        FROM translation_versions
        WHERE unit_id IN ($placeholders)
          AND project_language_id = ?
          AND (translated_text IS NULL OR translated_text = '')
        ''',
        [...ids, projectLanguageId],
      );

      return maps.map((map) => map['unit_id'] as String).toList();
    });
  }

  /// Get IDs of units that are already translated.
  ///
  /// Performance optimization: Batched queries to avoid N individual queries
  /// while staying within SQLite's parameter limit (999 max).
  /// Returns only unit IDs that have non-empty translated_text.
  Future<Result<Set<String>, TWMTDatabaseException>> getTranslatedUnitIds({
    required List<String> unitIds,
    required String projectLanguageId,
  }) async {
    if (unitIds.isEmpty) {
      return Ok(<String>{});
    }

    return executeQuery(() async {
      // SQLite has a limit on number of parameters (default 999)
      // We use 1 param for projectLanguageId, so batch unitIds at 500
      const batchSize = 500;
      final results = <String>{};

      for (var i = 0; i < unitIds.length; i += batchSize) {
        final batch = unitIds.skip(i).take(batchSize).toList();
        final placeholders = List.filled(batch.length, '?').join(',');

        final maps = await database.rawQuery(
          '''
          SELECT unit_id FROM $tableName
          WHERE unit_id IN ($placeholders)
            AND project_language_id = ?
            AND translated_text IS NOT NULL
            AND translated_text != ''
          ''',
          [...batch, projectLanguageId],
        );

        results.addAll(maps.map((m) => m['unit_id'] as String));
      }

      return results;
    });
  }

  /// Get translation version by unit and project language.
  Future<Result<TranslationVersion, TWMTDatabaseException>>
      getByUnitAndProjectLanguage({
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

  /// Clear translations for multiple versions.
  ///
  /// Sets translated_text to empty, status to pending, and updates timestamp.
  /// Batches queries to stay within SQLite's parameter limit (999 max).
  ///
  /// [versionIds] - List of version IDs to clear
  /// [onProgress] - Optional callback for progress reporting
  ///
  /// Returns the count of affected rows.
  Future<Result<int, TWMTDatabaseException>> clearBatch(
    List<String> versionIds, {
    void Function(int processed, int total, String phase)? onProgress,
  }) async {
    if (versionIds.isEmpty) {
      return Ok(0);
    }

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int totalAffected = 0;
      final total = versionIds.length;

      // For batches > 50, temporarily disable the progress trigger
      // This trigger recalculates stats with COUNT on every single UPDATE, which is very slow
      final disableProgressTrigger = versionIds.length > 50;

      if (disableProgressTrigger) {
        await txn.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');
      }

      try {
        // Process in batches to stay within SQLite parameter limits
        const batchSize = 500;

        for (var i = 0; i < versionIds.length; i += batchSize) {
          final batch = versionIds.skip(i).take(batchSize).toList();
          final placeholders = List.filled(batch.length, '?').join(',');

          final rowsAffected = await txn.rawUpdate(
            '''
            UPDATE $tableName
            SET translated_text = '',
                status = 'pending',
                updated_at = ?
            WHERE id IN ($placeholders)
            ''',
            [now, ...batch],
          );
          totalAffected += rowsAffected;

          final processed = (i + batch.length).clamp(0, total);
          onProgress?.call(processed, total, 'Clearing translations...');
        }

        if (disableProgressTrigger) {
          // Manually update project language progress once at the end
          onProgress?.call(total, total, 'Updating statistics...');
          await txn.rawUpdate('''
            UPDATE project_languages
            SET progress_percent = (
              SELECT
                CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                NULLIF(COUNT(*), 0)
              FROM translation_versions tv
              INNER JOIN translation_units tu ON tv.unit_id = tu.id
              WHERE tv.project_language_id = project_languages.id
                AND tu.is_obsolete = 0
            ),
            updated_at = ?
          ''', [now]);
        }
      } finally {
        if (disableProgressTrigger) {
          // Recreate the progress trigger
          await txn.execute('''
            CREATE TRIGGER trg_update_project_language_progress
            AFTER UPDATE ON translation_versions
            WHEN NEW.status != OLD.status
            BEGIN
              UPDATE project_languages
              SET progress_percent = (
                SELECT
                  CAST(COUNT(CASE WHEN tv.status IN ('approved', 'reviewed', 'translated') THEN 1 END) AS REAL) * 100.0 /
                  NULLIF(COUNT(*), 0)
                FROM translation_versions tv
                INNER JOIN translation_units tu ON tv.unit_id = tu.id
                WHERE tv.project_language_id = NEW.project_language_id
                  AND tu.is_obsolete = 0
              ),
              updated_at = strftime('%s', 'now')
              WHERE id = NEW.project_language_id;
            END
          ''');
        }
      }

      return totalAffected;
    });
  }

  /// Reset status to pending for all translation versions of specified units.
  ///
  /// Used when source text has changed and translations need to be reviewed.
  /// Does NOT clear the translated_text - only changes status to pending.
  /// Batches queries to stay within SQLite's parameter limit (999 max).
  ///
  /// [projectId] - The project containing the units
  /// [unitKeys] - List of unit keys to reset
  /// [onProgress] - Optional callback for progress reporting
  ///
  /// Returns the count of affected rows.
  Future<Result<int, TWMTDatabaseException>> resetStatusForUnitKeys({
    required String projectId,
    required List<String> unitKeys,
    void Function(int processed, int total)? onProgress,
  }) async {
    if (unitKeys.isEmpty) {
      return Ok(0);
    }

    return executeQuery(() async {
      // SQLite has a limit on number of parameters (default 999)
      // We use 2 params for timestamp and projectId, so batch unitKeys at 500
      const batchSize = 500;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final total = unitKeys.length;
      int totalAffected = 0;

      for (var i = 0; i < unitKeys.length; i += batchSize) {
        final batch = unitKeys.skip(i).take(batchSize).toList();
        final placeholders = List.filled(batch.length, '?').join(',');

        final rowsAffected = await database.rawUpdate(
          '''
          UPDATE $tableName
          SET status = 'pending',
              updated_at = ?
          WHERE unit_id IN (
            SELECT id FROM translation_units
            WHERE project_id = ? AND key IN ($placeholders)
          )
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

  /// Set status to needsReview for all translation versions of specified units.
  ///
  /// Used when obsolete units are reactivated and need review.
  /// Does NOT clear the translated_text - only changes status to needsReview.
  /// Batches queries to stay within SQLite's parameter limit (999 max).
  /// Returns the count of affected rows.
  Future<Result<int, TWMTDatabaseException>> setNeedsReviewForUnitKeys({
    required String projectId,
    required List<String> unitKeys,
  }) async {
    if (unitKeys.isEmpty) {
      return Ok(0);
    }

    return executeQuery(() async {
      // SQLite has a limit on number of parameters (default 999)
      // We use 2 params for timestamp and projectId, so batch unitKeys at 500
      const batchSize = 500;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      int totalAffected = 0;

      for (var i = 0; i < unitKeys.length; i += batchSize) {
        final batch = unitKeys.skip(i).take(batchSize).toList();
        final placeholders = List.filled(batch.length, '?').join(',');

        final rowsAffected = await database.rawUpdate(
          '''
          UPDATE $tableName
          SET status = 'needsReview',
              updated_at = ?
          WHERE unit_id IN (
            SELECT id FROM translation_units
            WHERE project_id = ? AND key IN ($placeholders)
          )
          ''',
          [now, projectId, ...batch],
        );
        totalAffected += rowsAffected;
      }

      return totalAffected;
    });
  }

  /// Reanalyze all translation versions to fix status inconsistencies.
  ///
  /// This method:
  /// 1. Sets status to 'pending' for versions with empty/null translated_text
  ///    but non-pending status
  /// 2. Sets status to 'translated' for versions with non-empty translated_text
  ///    but 'pending' or 'translating' status (and not manually edited/validated)
  ///
  /// Returns a record with the count of fixed entries and total analyzed.
  Future<Result<({int fixedToPending, int fixedToTranslated, int total}),
      TWMTDatabaseException>> reanalyzeAllStatuses() async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Count total versions
      final countResult = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName',
      );
      final total = (countResult.first['count'] as int?) ?? 0;

      // Fix versions that have no translation but non-pending status
      // (excluding 'translating' which is a valid in-progress state)
      final fixedToPending = await database.rawUpdate(
        '''
        UPDATE $tableName
        SET status = 'pending',
            updated_at = ?
        WHERE (translated_text IS NULL OR translated_text = '')
          AND status NOT IN ('pending', 'translating')
        ''',
        [now],
      );

      // Fix versions that have translation but still show as pending
      // Don't touch manually edited or validated entries
      final fixedToTranslated = await database.rawUpdate(
        '''
        UPDATE $tableName
        SET status = 'translated',
            updated_at = ?
        WHERE translated_text IS NOT NULL
          AND translated_text != ''
          AND status IN ('pending', 'translating')
          AND is_manually_edited = 0
        ''',
        [now],
      );

      return (
        fixedToPending: fixedToPending,
        fixedToTranslated: fixedToTranslated,
        total: total,
      );
    });
  }

  /// Count versions with inconsistent status.
  ///
  /// Returns the count of versions where status doesn't match translated_text state.
  Future<Result<({int pendingWithText, int nonPendingWithoutText}),
      TWMTDatabaseException>> countInconsistentStatuses() async {
    return executeQuery(() async {
      // Versions with translation but pending/translating status
      final pendingWithTextResult = await database.rawQuery(
        '''
        SELECT COUNT(*) as count FROM $tableName
        WHERE translated_text IS NOT NULL
          AND translated_text != ''
          AND status IN ('pending', 'translating')
          AND is_manually_edited = 0
        ''',
      );
      final pendingWithText =
          (pendingWithTextResult.first['count'] as int?) ?? 0;

      // Versions without translation but non-pending status
      final nonPendingResult = await database.rawQuery(
        '''
        SELECT COUNT(*) as count FROM $tableName
        WHERE (translated_text IS NULL OR translated_text = '')
          AND status NOT IN ('pending', 'translating')
        ''',
      );
      final nonPendingWithoutText =
          (nonPendingResult.first['count'] as int?) ?? 0;

      return (
        pendingWithText: pendingWithText,
        nonPendingWithoutText: nonPendingWithoutText,
      );
    });
  }
}
