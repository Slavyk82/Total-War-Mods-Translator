import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import '../translation_version_triggers.dart';
import 'migration_base.dart';

/// Migration to rebuild `translation_versions_fts` with
/// `contentless_delete=1, contentless_unindexed=1`.
///
/// The legacy schema declared the table as plain contentless FTS5
/// (`content=''`). A plain contentless table stores NO column values, so:
///
/// 1. `version_id` read back NULL on every row — the search query's
///    `INNER JOIN ... ON fts.version_id = tv.id` matched nothing and in-app
///    search of translated text silently returned zero results.
/// 2. Every `DELETE FROM translation_versions_fts WHERE version_id = ...`
///    (schema triggers and repository bulk maintenance) was a no-op, so
///    stale/duplicate index entries accumulated forever.
///
/// With `contentless_unindexed=1` (SQLite >= 3.47; the app bundles 3.51)
/// UNINDEXED column values ARE stored and readable, and with
/// `contentless_delete=1` DELETE statements actually remove entries. This
/// migration drops the broken table (and its sync triggers), recreates both
/// with the new options, and repopulates the index from
/// `translation_versions`. schema.sql has been fixed for fresh installs.
class ContentlessFtsVersionIdMigration extends Migration {
  final ILoggingService _logger;

  ContentlessFtsVersionIdMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  static const String _tableName = 'translation_versions_fts';

  /// Verbatim from schema.sql (the insert/update triggers come from
  /// [TranslationVersionTriggers], the single source of truth bulk paths
  /// already use; the delete trigger has no shared constant).
  static const String _ftsDeleteTrigger = '''
    CREATE TRIGGER IF NOT EXISTS trg_translation_versions_fts_delete
    AFTER DELETE ON translation_versions
    BEGIN
      DELETE FROM translation_versions_fts WHERE version_id = old.id;
    END
  ''';

  @override
  String get id => 'contentless_fts_version_id';

  @override
  String get description =>
      'Rebuild translation_versions_fts with contentless_delete=1 + '
      'contentless_unindexed=1 so version_id is stored (search JOIN works) '
      'and DELETE maintenance actually removes entries';

  @override
  int get priority => 230;

  @override
  Future<bool> isApplied() async {
    final rows = await DatabaseService.database.rawQuery(
      "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?",
      [_tableName],
    );
    if (rows.isEmpty) {
      // Table missing entirely: not applied — execute() recreates it.
      return false;
    }
    final sql = (rows.first['sql'] as String?) ?? '';
    return sql.contains('contentless_delete');
  }

  @override
  Future<bool> execute() async {
    try {
      if (await isApplied()) {
        return false; // Already rebuilt with the new options.
      }

      final db = DatabaseService.database;
      await db.transaction((txn) async {
        // Drop the sync triggers first so the table drop cannot race a
        // concurrent write, then the broken table itself.
        await txn
            .execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_insert');
        await txn
            .execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_update');
        await txn
            .execute('DROP TRIGGER IF EXISTS trg_translation_versions_fts_delete');
        await txn.execute('DROP TABLE IF EXISTS $_tableName');

        // Recreate with stored UNINDEXED columns + working DELETE.
        // Keep in sync with lib/database/schema.sql.
        await txn.execute('''
          CREATE VIRTUAL TABLE $_tableName USING fts5(
              translated_text,
              validation_issues,
              version_id UNINDEXED,
              content='',
              contentless_delete=1,
              contentless_unindexed=1
          )
        ''');

        // Recreate the three sync triggers exactly as schema.sql defines them.
        await txn.execute(TranslationVersionTriggers.ftsInsert);
        await txn.execute(TranslationVersionTriggers.ftsUpdate);
        await txn.execute(_ftsDeleteTrigger);

        // Repopulate the index from the source of truth.
        await txn.execute('''
          INSERT INTO $_tableName(translated_text, validation_issues, version_id)
          SELECT translated_text, validation_issues, id
          FROM translation_versions
          WHERE translated_text IS NOT NULL
        ''');
      });

      _logger.info(
        'Rebuilt $_tableName with contentless_delete=1 + contentless_unindexed=1',
      );
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to rebuild $_tableName', e, stackTrace);
      return false;
    }
  }
}
