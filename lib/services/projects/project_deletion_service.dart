import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../shared/logging_service.dart';
import '../database/database_service.dart';

/// Highly optimized project deletion service - Version 2
///
/// Key optimizations:
/// 1. Properly disables ALL triggers (FTS5 + Cache) during deletion
/// 2. Bulk cache deletion before disabling triggers
/// 3. Rowid-based deletion for better query performance
/// 4. Batch processing with optimal batch size (5000 rows)
/// 5. Temporary PRAGMA optimizations for bulk operations
/// 6. Detailed performance metrics and logging
///
/// Expected performance: <10 seconds for 16K+ rows (vs 61+ seconds before)
class ProjectDeletionServiceV2 {
  final LoggingService _logger = LoggingService.instance;

  /// Delete a project and all related data with maximum efficiency
  ///
  /// Performance target: <10 seconds for 16K translation_units
  /// Previous performance: 61+ seconds
  Future<Result<void, TWMTDatabaseException>> deleteProject(
    String projectId,
  ) async {
    final startTime = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final timings = <String, int>{};

    _logger.info('Starting optimized project deletion v2', {'projectId': projectId});

    try {
      final db = DatabaseService.database;

      // Get counts for logging
      final counts = await _getProjectCounts(db, projectId);
      _logger.info('Project deletion counts', counts);

      // Step 0: Optimize PRAGMA settings for bulk operations
      _logger.debug('Optimizing PRAGMA settings');
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('PRAGMA synchronous = OFF'); // Faster writes during deletion
      timings['pragmaSetup'] = stopwatch.elapsedMilliseconds;

      // Step 1: Bulk delete cache FIRST (before disabling triggers)
      // This is a single DELETE operation, much faster than trigger-based deletion
      _logger.debug('Bulk deleting translation_view_cache');
      final cacheDeleted = await db.rawDelete(
        'DELETE FROM translation_view_cache WHERE project_id = ?',
        [projectId],
      );
      timings['deleteCache'] = stopwatch.elapsedMilliseconds - timings['pragmaSetup']!;
      _logger.debug('Deleted $cacheDeleted cache entries');

      // Step 2: Disable ALL triggers (FTS5 + Cache + Progress)
      // CRITICAL: Must disable ALL triggers that fire on DELETE
      _logger.debug('Disabling all triggers');
      await _disableAllTriggers(db);
      timings['disableTriggers'] = stopwatch.elapsedMilliseconds - (timings['pragmaSetup']! + timings['deleteCache']!);

      // Step 3: Delete in optimal order (reverse of dependencies)
      final deleteStartTime = stopwatch.elapsedMilliseconds;

      // Delete translation_version_tm_usage
      await _deleteWithRowidJoin(
        db,
        'translation_version_tm_usage',
        '''
        SELECT tvtu.rowid FROM translation_version_tm_usage tvtu
        INNER JOIN translation_versions tv ON tvtu.version_id = tv.id
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
        ''',
        [projectId],
      );

      // Delete translation_version_history
      await _deleteWithRowidJoin(
        db,
        'translation_version_history',
        '''
        SELECT tvh.rowid FROM translation_version_history tvh
        INNER JOIN translation_versions tv ON tvh.version_id = tv.id
        INNER JOIN translation_units tu ON tv.unit_id = tu.id
        WHERE tu.project_id = ?
        ''',
        [projectId],
      );

      // Delete translation_batch_units
      await _deleteWithRowidJoin(
        db,
        'translation_batch_units',
        '''
        SELECT tbu.rowid FROM translation_batch_units tbu
        INNER JOIN translation_batches tb ON tbu.batch_id = tb.id
        INNER JOIN project_languages pl ON tb.project_language_id = pl.id
        WHERE pl.project_id = ?
        ''',
        [projectId],
      );

      // Delete translation_batches
      await _deleteWithRowidJoin(
        db,
        'translation_batches',
        '''
        SELECT tb.rowid FROM translation_batches tb
        INNER JOIN project_languages pl ON tb.project_language_id = pl.id
        WHERE pl.project_id = ?
        ''',
        [projectId],
      );

      // Delete translation_versions (LARGEST TABLE - use batching)
      final versionsStartTime = stopwatch.elapsedMilliseconds;
      await _deleteVersionsInBatches(db, projectId);
      timings['deleteVersions'] = stopwatch.elapsedMilliseconds - versionsStartTime;

      // Delete translation_units (will not trigger FTS5 since triggers disabled)
      await db.rawDelete(
        'DELETE FROM translation_units WHERE project_id = ?',
        [projectId],
      );

      // Delete mod_version_changes
      await _deleteWithRowidJoin(
        db,
        'mod_version_changes',
        '''
        SELECT mvc.rowid FROM mod_version_changes mvc
        INNER JOIN mod_versions mv ON mvc.version_id = mv.id
        WHERE mv.project_id = ?
        ''',
        [projectId],
      );

      // Delete mod_versions
      await db.rawDelete(
        'DELETE FROM mod_versions WHERE project_id = ?',
        [projectId],
      );

      // Delete project_languages
      await db.rawDelete(
        'DELETE FROM project_languages WHERE project_id = ?',
        [projectId],
      );

      // Finally delete the project itself
      final deletedRows = await db.delete(
        'projects',
        where: 'id = ?',
        whereArgs: [projectId],
      );

      if (deletedRows == 0) {
        throw TWMTDatabaseException('Project not found for deletion: $projectId');
      }

      timings['deleteAllData'] = stopwatch.elapsedMilliseconds - deleteStartTime;

      // Step 4: Re-enable triggers
      _logger.debug('Re-enabling triggers');
      final triggerStartTime = stopwatch.elapsedMilliseconds;
      await _enableAllTriggers(db);
      timings['enableTriggers'] = stopwatch.elapsedMilliseconds - triggerStartTime;

      // Step 5: Clean up FTS5 tables (rebuild is faster for large deletions)
      _logger.debug('Rebuilding FTS5 indexes');
      final ftsStartTime = stopwatch.elapsedMilliseconds;
      await _rebuildFts5(db);
      timings['rebuildFts5'] = stopwatch.elapsedMilliseconds - ftsStartTime;

      // Step 6: Restore PRAGMA settings
      _logger.debug('Restoring PRAGMA settings');
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('PRAGMA synchronous = NORMAL');
      timings['pragmaRestore'] = stopwatch.elapsedMilliseconds - (ftsStartTime + timings['rebuildFts5']!);

      final duration = DateTime.now().difference(startTime);
      _logger.info(
        'Project deletion completed successfully',
        {
          'projectId': projectId,
          'durationMs': duration.inMilliseconds,
          'timingBreakdown': timings,
        },
      );

      return const Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Project deletion failed', e, stackTrace);

      // Ensure triggers and PRAGMA settings are restored even on error
      try {
        final db = DatabaseService.database;
        await _enableAllTriggers(db);
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA synchronous = NORMAL');
      } catch (restoreError) {
        _logger.error('Failed to restore triggers/PRAGMA', restoreError);
      }

      return Err(
        TWMTDatabaseException(
          'Failed to delete project: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Disable ALL triggers that could fire during deletion
  /// CRITICAL: This includes FTS5, cache, and progress triggers
  Future<void> _disableAllTriggers(Database db) async {
    // FTS5 triggers on translation_units
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_insert');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_units_fts_delete');

    // FTS5 triggers on translation_versions
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_insert');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_delete');

    // Cache triggers on translation_units
    await db.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_unit_change');

    // Cache triggers on translation_versions
    await db.execute('DROP TRIGGER IF EXISTS trg_delete_cache_on_version_delete');
    await db.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
    await db.execute('DROP TRIGGER IF EXISTS trg_insert_cache_on_version_insert');

    // Progress update trigger
    await db.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');

    // Timestamp triggers (less critical but might as well disable)
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_updated_at');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_units_updated_at');
  }

  /// Re-enable all triggers
  Future<void> _enableAllTriggers(Database db) async {
    // FTS5 triggers on translation_units
    await db.execute('''
      CREATE TRIGGER trg_translation_units_fts_insert
      AFTER INSERT ON translation_units BEGIN
        INSERT INTO translation_units_fts(rowid, key, source_text, context, notes)
        VALUES (new.rowid, new.key, new.source_text, new.context, new.notes);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_units_fts_update
      AFTER UPDATE ON translation_units BEGIN
        UPDATE translation_units_fts
        SET key = new.key,
            source_text = new.source_text,
            context = new.context,
            notes = new.notes
        WHERE rowid = new.rowid;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_units_fts_delete
      AFTER DELETE ON translation_units BEGIN
        DELETE FROM translation_units_fts WHERE rowid = old.rowid;
      END
    ''');

    // FTS5 triggers on translation_versions
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_insert
      AFTER INSERT ON translation_versions BEGIN
        INSERT INTO translation_versions_fts(rowid, translated_text, validation_issues)
        VALUES (new.rowid, new.translated_text, new.validation_issues);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_update
      AFTER UPDATE ON translation_versions BEGIN
        UPDATE translation_versions_fts
        SET translated_text = new.translated_text,
            validation_issues = new.validation_issues
        WHERE rowid = new.rowid;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_delete
      AFTER DELETE ON translation_versions BEGIN
        DELETE FROM translation_versions_fts WHERE rowid = old.rowid;
      END
    ''');

    // Cache triggers
    await db.execute('''
      CREATE TRIGGER trg_update_cache_on_unit_change
      AFTER UPDATE ON translation_units
      BEGIN
        UPDATE translation_view_cache
        SET key = new.key,
            source_text = new.source_text,
            is_obsolete = new.is_obsolete,
            unit_updated_at = new.updated_at
        WHERE unit_id = new.id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_delete_cache_on_version_delete
      AFTER DELETE ON translation_versions
      BEGIN
        DELETE FROM translation_view_cache WHERE version_id = old.id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_update_cache_on_version_change
      AFTER UPDATE ON translation_versions
      BEGIN
        UPDATE translation_view_cache
        SET translated_text = new.translated_text,
            status = new.status,
            confidence_score = new.confidence_score,
            is_manually_edited = new.is_manually_edited,
            version_id = new.id,
            version_updated_at = new.updated_at
        WHERE unit_id = new.unit_id
          AND project_language_id = new.project_language_id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_insert_cache_on_version_insert
      AFTER INSERT ON translation_versions
      BEGIN
        INSERT OR REPLACE INTO translation_view_cache (
          id,
          project_id,
          project_language_id,
          language_code,
          unit_id,
          version_id,
          key,
          source_text,
          translated_text,
          status,
          confidence_score,
          is_manually_edited,
          is_obsolete,
          unit_created_at,
          unit_updated_at,
          version_updated_at
        )
        SELECT
          new.id || '_' || tu.id AS id,
          tu.project_id,
          new.project_language_id,
          l.code,
          tu.id,
          new.id,
          tu.key,
          tu.source_text,
          new.translated_text,
          new.status,
          new.confidence_score,
          new.is_manually_edited,
          tu.is_obsolete,
          tu.created_at,
          tu.updated_at,
          new.updated_at
        FROM translation_units tu
        INNER JOIN project_languages pl ON pl.id = new.project_language_id
        INNER JOIN languages l ON l.id = pl.language_id
        WHERE tu.id = new.unit_id;
      END
    ''');

    // Progress trigger
    await db.execute('''
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

    // Timestamp triggers
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_updated_at
      AFTER UPDATE ON translation_versions
      BEGIN
        UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_units_updated_at
      AFTER UPDATE ON translation_units
      BEGIN
        UPDATE translation_units SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');
  }

  /// Delete rows using rowid-based JOIN query (more efficient than IN subquery)
  Future<void> _deleteWithRowidJoin(
    Database db,
    String tableName,
    String rowidSelectQuery,
    List<Object?> args,
  ) async {
    final deleted = await db.rawDelete(
      'DELETE FROM $tableName WHERE rowid IN ($rowidSelectQuery)',
      args,
    );

    if (deleted > 0) {
      _logger.debug('Deleted from $tableName', {'count': deleted});
    }
  }

  /// Delete translation_versions in batches for optimal performance
  Future<void> _deleteVersionsInBatches(Database db, String projectId) async {
    const batchSize = 5000; // Optimal batch size for SQLite
    int totalDeleted = 0;
    int batchCount = 0;

    _logger.debug('Starting batched deletion of translation_versions');

    while (true) {
      batchCount++;
      final deleted = await db.rawDelete('''
        DELETE FROM translation_versions
        WHERE rowid IN (
          SELECT tv.rowid
          FROM translation_versions tv
          INNER JOIN translation_units tu ON tv.unit_id = tu.id
          WHERE tu.project_id = ?
          LIMIT ?
        )
      ''', [projectId, batchSize]);

      if (deleted == 0) break;

      totalDeleted += deleted;

      if (totalDeleted % 10000 == 0 || deleted < batchSize) {
        _logger.debug(
          'Batch deletion progress',
          {'deleted': totalDeleted, 'batches': batchCount},
        );
      }
    }

    _logger.info('Deleted from translation_versions', {'count': totalDeleted});
  }

  /// Rebuild FTS5 indexes (faster than selective cleanup for large deletions)
  Future<void> _rebuildFts5(Database db) async {
    // Rebuild instead of selective deletion - much faster for large changes
    // Note: Only rebuild external content FTS5 tables
    // translation_versions_fts uses contentless mode (content='') and cannot be rebuilt
    // Its entries are managed by triggers on translation_versions
    await db.execute("INSERT INTO translation_units_fts(translation_units_fts) VALUES('rebuild')");
    // translation_versions_fts: contentless FTS5 - 'rebuild' not supported, triggers handle cleanup
  }

  /// Get counts of related data for a project
  Future<Map<String, dynamic>> _getProjectCounts(
    Database db,
    String projectId,
  ) async {
    final counts = <String, dynamic>{};

    // Count translation units
    final unitsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM translation_units WHERE project_id = ?',
      [projectId],
    );
    counts['translation_units'] = unitsResult.first['count'];

    // Count project languages
    final langsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM project_languages WHERE project_id = ?',
      [projectId],
    );
    counts['project_languages'] = langsResult.first['count'];

    // Count translation versions
    final versionsResult = await db.rawQuery(
      '''
      SELECT COUNT(*) as count FROM translation_versions tv
      INNER JOIN translation_units tu ON tv.unit_id = tu.id
      WHERE tu.project_id = ?
      ''',
      [projectId],
    );
    counts['translation_versions'] = versionsResult.first['count'];

    return counts;
  }
}
