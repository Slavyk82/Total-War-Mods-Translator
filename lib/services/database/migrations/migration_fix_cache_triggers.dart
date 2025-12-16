import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to fix cache triggers that reference non-existent confidence_score column.
///
/// The translation_versions table does not have a confidence_score column, but
/// the cache triggers were incorrectly referencing new.confidence_score.
/// This migration drops and recreates the affected triggers with NULL instead.
///
/// Additionally, this migration repairs any missing translation_versions that
/// may have failed to be created due to the broken triggers.
class FixCacheTriggersMigration extends Migration {
  @override
  String get id => 'fix_cache_triggers_confidence_score';

  @override
  String get description =>
      'Fix cache triggers and repair missing translation_versions';

  @override
  int get priority => 101; // Run after other migrations

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      logging.info('Fixing cache triggers for confidence_score bug');

      // Drop the broken triggers (IF EXISTS ensures idempotency)
      await DatabaseService.execute(
          'DROP TRIGGER IF EXISTS trg_update_cache_on_version_change');
      await DatabaseService.execute(
          'DROP TRIGGER IF EXISTS trg_insert_cache_on_version_insert');

      // Recreate trg_update_cache_on_version_change with NULL instead of new.confidence_score
      await DatabaseService.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_update_cache_on_version_change
        AFTER UPDATE ON translation_versions
        BEGIN
          UPDATE translation_view_cache
          SET translated_text = new.translated_text,
              status = new.status,
              confidence_score = NULL,
              is_manually_edited = new.is_manually_edited,
              version_id = new.id,
              version_updated_at = new.updated_at
          WHERE unit_id = new.unit_id
            AND project_language_id = new.project_language_id;
        END
      ''');

      // Recreate trg_insert_cache_on_version_insert with NULL instead of new.confidence_score
      await DatabaseService.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_insert_cache_on_version_insert
        AFTER INSERT ON translation_versions
        BEGIN
          INSERT OR REPLACE INTO translation_view_cache (
            id, project_id, project_language_id, language_code, unit_id, version_id,
            key, source_text, translated_text, status, confidence_score,
            is_manually_edited, is_obsolete, unit_created_at, unit_updated_at, version_updated_at
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
            NULL,
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

      logging.info('Cache triggers fixed successfully');

      // Repair missing translation_versions
      await _repairMissingTranslationVersions(logging);

      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to fix cache triggers', e, stackTrace);
      // This is a critical migration - re-throw to alert the user
      rethrow;
    }
  }

  /// Repair missing translation_versions entries.
  ///
  /// For each project_language, checks if there are translation_units without
  /// corresponding translation_versions and creates them.
  /// The INSERT trigger will automatically populate translation_view_cache.
  Future<void> _repairMissingTranslationVersions(LoggingService logging) async {
    // Count missing versions
    final countResult = await DatabaseService.database.rawQuery('''
      SELECT COUNT(*) as cnt
      FROM translation_units tu
      CROSS JOIN project_languages pl ON tu.project_id = pl.project_id
      WHERE NOT EXISTS (
        SELECT 1 FROM translation_versions tv
        WHERE tv.unit_id = tu.id AND tv.project_language_id = pl.id
      )
    ''');

    final missingCount = (countResult.first['cnt'] as int?) ?? 0;

    if (missingCount == 0) {
      logging.debug('No missing translation_versions found');
      return;
    }

    logging.info('Found $missingCount missing translation_versions, repairing...');

    // Insert missing translation_versions
    // Uses UUID v4 format generated in SQL for the id
    // The INSERT trigger will automatically populate translation_view_cache
    final insertedCount = await DatabaseService.database.rawInsert('''
      INSERT INTO translation_versions (
        id, unit_id, project_language_id, translated_text, is_manually_edited,
        status, translation_source, validation_issues, created_at, updated_at
      )
      SELECT
        lower(hex(randomblob(4)) || '-' || hex(randomblob(2)) || '-4' ||
              substr(hex(randomblob(2)),2) || '-' ||
              substr('89ab',abs(random()) % 4 + 1, 1) ||
              substr(hex(randomblob(2)),2) || '-' || hex(randomblob(6))),
        tu.id,
        pl.id,
        NULL,
        0,
        'pending',
        'unknown',
        NULL,
        strftime('%s', 'now'),
        strftime('%s', 'now')
      FROM translation_units tu
      CROSS JOIN project_languages pl ON tu.project_id = pl.project_id
      WHERE NOT EXISTS (
        SELECT 1 FROM translation_versions tv
        WHERE tv.unit_id = tu.id AND tv.project_language_id = pl.id
      )
    ''');

    logging.info('Repaired $insertedCount missing translation_versions');
  }
}
