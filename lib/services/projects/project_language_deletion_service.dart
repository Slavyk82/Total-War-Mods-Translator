import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../shared/logging_service.dart';
import '../database/database_service.dart';

/// Optimized project language deletion service.
///
/// Key optimizations:
/// 1. Disables triggers during deletion to avoid cascade overhead
/// 2. Bulk deletes translation_versions in batches
/// 3. Deletes cache entries before disabling triggers
/// 4. Re-enables triggers and rebuilds FTS5 indexes after deletion
class ProjectLanguageDeletionService {
  final LoggingService _logger = LoggingService.instance;

  /// Delete a project language and all related translation versions.
  ///
  /// This is much faster than relying on CASCADE DELETE because it:
  /// - Disables triggers during deletion
  /// - Deletes in optimal order
  /// - Uses batch deletion for large datasets
  Future<Result<void, TWMTDatabaseException>> deleteProjectLanguage(
    String projectLanguageId,
  ) async {
    final startTime = DateTime.now();
    final stopwatch = Stopwatch()..start();

    _logger.info('Starting optimized project language deletion', {
      'projectLanguageId': projectLanguageId,
    });

    try {
      final db = DatabaseService.database;

      // Get counts for logging
      final counts = await _getProjectLanguageCounts(db, projectLanguageId);
      _logger.info('Project language deletion counts', counts);

      // If there are no versions, just delete the project_language directly
      if ((counts['translation_versions'] as int) == 0) {
        final deleted = await db.delete(
          'project_languages',
          where: 'id = ?',
          whereArgs: [projectLanguageId],
        );

        if (deleted == 0) {
          throw TWMTDatabaseException(
            'Project language not found: $projectLanguageId',
          );
        }

        _logger.info('Project language deleted (no versions)', {
          'projectLanguageId': projectLanguageId,
          'durationMs': stopwatch.elapsedMilliseconds,
        });

        return const Ok(null);
      }

      // Step 1: Optimize PRAGMA settings
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.execute('PRAGMA synchronous = OFF');

      // Step 2: Delete cache entries for this project language
      _logger.debug('Deleting cache entries');
      await db.rawDelete(
        'DELETE FROM translation_view_cache WHERE project_language_id = ?',
        [projectLanguageId],
      );

      // Step 3: Disable triggers
      _logger.debug('Disabling triggers');
      await _disableTriggers(db);

      // Step 4: Delete translation_version_tm_usage
      await db.rawDelete(
        '''
        DELETE FROM translation_version_tm_usage
        WHERE version_id IN (
          SELECT id FROM translation_versions WHERE project_language_id = ?
        )
        ''',
        [projectLanguageId],
      );

      // Step 5: Delete translation_version_history
      await db.rawDelete(
        '''
        DELETE FROM translation_version_history
        WHERE version_id IN (
          SELECT id FROM translation_versions WHERE project_language_id = ?
        )
        ''',
        [projectLanguageId],
      );

      // Step 6: Delete translation_batch_units
      await db.rawDelete(
        '''
        DELETE FROM translation_batch_units
        WHERE batch_id IN (
          SELECT id FROM translation_batches WHERE project_language_id = ?
        )
        ''',
        [projectLanguageId],
      );

      // Step 7: Delete translation_batches
      await db.rawDelete(
        'DELETE FROM translation_batches WHERE project_language_id = ?',
        [projectLanguageId],
      );

      // Step 8: Delete translation_versions in batches
      _logger.debug('Deleting translation versions');
      await _deleteVersionsInBatches(db, projectLanguageId);

      // Step 9: Delete the project_language itself
      final deleted = await db.delete(
        'project_languages',
        where: 'id = ?',
        whereArgs: [projectLanguageId],
      );

      if (deleted == 0) {
        throw TWMTDatabaseException(
          'Project language not found: $projectLanguageId',
        );
      }

      // Step 10: Re-enable triggers
      _logger.debug('Re-enabling triggers');
      await _enableTriggers(db);

      // Step 11: Rebuild FTS5 for translation_versions (contentless - managed by triggers)
      // No rebuild needed for contentless FTS5

      // Step 12: Restore PRAGMA settings
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('PRAGMA synchronous = NORMAL');

      final duration = DateTime.now().difference(startTime);
      _logger.info('Project language deletion completed', {
        'projectLanguageId': projectLanguageId,
        'durationMs': duration.inMilliseconds,
        'versionsDeleted': counts['translation_versions'],
      });

      return const Ok(null);
    } catch (e, stackTrace) {
      _logger.error('Project language deletion failed', e, stackTrace);

      // Ensure triggers and PRAGMA are restored on error
      try {
        final db = DatabaseService.database;
        await _enableTriggers(db);
        await db.execute('PRAGMA foreign_keys = ON');
        await db.execute('PRAGMA synchronous = NORMAL');
      } catch (restoreError) {
        _logger.error('Failed to restore triggers/PRAGMA', restoreError);
      }

      return Err(
        TWMTDatabaseException(
          'Failed to delete project language: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Delete translation_versions in batches
  Future<void> _deleteVersionsInBatches(
    Database db,
    String projectLanguageId,
  ) async {
    const batchSize = 5000;
    int totalDeleted = 0;

    while (true) {
      final deleted = await db.rawDelete(
        '''
        DELETE FROM translation_versions
        WHERE rowid IN (
          SELECT rowid FROM translation_versions
          WHERE project_language_id = ?
          LIMIT ?
        )
        ''',
        [projectLanguageId, batchSize],
      );

      if (deleted == 0) break;
      totalDeleted += deleted;
    }

    _logger.debug('Deleted translation versions', {'count': totalDeleted});
  }

  /// Disable triggers that fire on DELETE
  Future<void> _disableTriggers(Database db) async {
    // FTS5 triggers on translation_versions
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_insert');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_delete');

    // Cache triggers
    await db.execute('DROP TRIGGER IF EXISTS trg_delete_cache_on_version_delete');
    await db.execute('DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
    await db.execute('DROP TRIGGER IF EXISTS trg_insert_cache_on_version_insert');

    // Progress trigger
    await db.execute('DROP TRIGGER IF EXISTS trg_update_project_language_progress');

    // Timestamp triggers
    await db.execute('DROP TRIGGER IF EXISTS trg_translation_versions_updated_at');
  }

  /// Re-enable triggers
  Future<void> _enableTriggers(Database db) async {
    // FTS5 triggers on translation_versions (contentless mode)
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_insert
      AFTER INSERT ON translation_versions
      WHEN new.translated_text IS NOT NULL
      BEGIN
        INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
        VALUES (new.translated_text, new.validation_issues, new.id);
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_update
      AFTER UPDATE OF translated_text, validation_issues ON translation_versions
      BEGIN
        DELETE FROM translation_versions_fts WHERE version_id = old.id;
        INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
        SELECT new.translated_text, new.validation_issues, new.id
        WHERE new.translated_text IS NOT NULL;
      END
    ''');

    await db.execute('''
      CREATE TRIGGER trg_translation_versions_fts_delete
      AFTER DELETE ON translation_versions
      BEGIN
        DELETE FROM translation_versions_fts WHERE version_id = old.id;
      END
    ''');

    // Cache triggers
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

    // Timestamp trigger
    await db.execute('''
      CREATE TRIGGER trg_translation_versions_updated_at
      AFTER UPDATE ON translation_versions
      BEGIN
        UPDATE translation_versions SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
      END
    ''');
  }

  /// Get counts of related data
  Future<Map<String, dynamic>> _getProjectLanguageCounts(
    Database db,
    String projectLanguageId,
  ) async {
    final counts = <String, dynamic>{};

    final versionsResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM translation_versions WHERE project_language_id = ?',
      [projectLanguageId],
    );
    counts['translation_versions'] = versionsResult.first['count'];

    final batchesResult = await db.rawQuery(
      'SELECT COUNT(*) as count FROM translation_batches WHERE project_language_id = ?',
      [projectLanguageId],
    );
    counts['translation_batches'] = batchesResult.first['count'];

    return counts;
  }
}
