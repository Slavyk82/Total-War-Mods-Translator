import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Single source of truth for the `translation_versions` triggers that bulk
/// paths temporarily DROP for performance and must recreate afterwards.
///
/// CREATE TRIGGER is a persisted schema change: a recreated trigger that
/// diverges from schema.sql permanently replaces the live one. A previous
/// inline copy of `trg_update_project_language_progress` omitted the
/// `UPDATE projects` bump, silently breaking the "Export outdated" filter
/// after every >50-row import or TM bulk apply. Every consumer (batch mixin,
/// repository helpers, startup recovery) must go through this class so the
/// DDL can never diverge again.
///
/// The definitions below MUST stay byte-for-byte equivalent to schema.sql.
class TranslationVersionTriggers {
  TranslationVersionTriggers._();

  /// schema.sql: trg_update_project_language_progress
  static const String updateProjectLanguageProgress = '''
    CREATE TRIGGER IF NOT EXISTS trg_update_project_language_progress
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

      UPDATE projects
      SET updated_at = strftime('%s', 'now')
      WHERE id = (
        SELECT project_id FROM project_languages
        WHERE id = NEW.project_language_id
      );
    END
  ''';

  /// schema.sql: trg_translation_versions_fts_insert
  static const String ftsInsert = '''
    CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_insert
    AFTER INSERT ON translation_versions
    WHEN new.translated_text IS NOT NULL
    BEGIN
      INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
      VALUES (new.translated_text, new.validation_issues, new.id);
    END
  ''';

  /// schema.sql: trg_translation_versions_fts_update
  static const String ftsUpdate = '''
    CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_update
    AFTER UPDATE OF translated_text, validation_issues ON translation_versions
    BEGIN
      DELETE FROM translation_versions_fts WHERE version_id = old.id;
      INSERT INTO translation_versions_fts(translated_text, validation_issues, version_id)
      SELECT new.translated_text, new.validation_issues, new.id
      WHERE new.translated_text IS NOT NULL;
    END
  ''';

  /// schema.sql: trg_update_cache_on_version_change
  static const String updateCacheOnVersionChange = '''
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
  ''';

  /// Trigger name -> canonical DDL, for callers that need to check existence
  /// (e.g. startup recovery after a crash mid-batch).
  static const Map<String, String> byName = {
    'trg_update_project_language_progress': updateProjectLanguageProgress,
    'trg_translation_versions_fts_insert': ftsInsert,
    'trg_translation_versions_fts_update': ftsUpdate,
    'trg_update_cache_on_version_change': updateCacheOnVersionChange,
  };

  /// Recreate every trigger a bulk path may have dropped. Idempotent
  /// (`CREATE TRIGGER IF NOT EXISTS`), safe inside or outside a transaction.
  static Future<void> recreateAll(DatabaseExecutor executor) async {
    for (final ddl in byName.values) {
      await executor.execute(ddl);
    }
  }
}
