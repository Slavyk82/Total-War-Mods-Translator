import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Reconciles existing databases whose `export_history` table predates the
/// "unified structure" schema refactor (commit e61691b).
///
/// Old databases store one row per language with a non-null `language_code`
/// column (e.g. `'fr'`). The current `ExportHistory` model and the canonical
/// `CREATE TABLE` (see [ExportHistoryRepository.ensureTableExists]) instead
/// expect a `languages` column holding a JSON array string (e.g. `'["fr"]'`).
///
/// Without this migration, on an upgraded database:
/// - every `export_history` row fails to deserialize — `fromJson` reads
///   `json['languages']`, which is null, throwing
///   "type 'Null' is not a subtype of type 'String' in type cast". This breaks
///   the Projects and Steam Publish screens, both of which read the last pack
///   export via `getLastPackExportByProject` (a raw, unwrapped query);
/// - new export records cannot be inserted, because the model omits
///   `language_code`, which is `NOT NULL` in the legacy schema.
///
/// This migration adds `languages`, backfills it from `language_code` (wrapping
/// the single code in a one-element JSON array), then drops the obsolete
/// `language_code` column so model-driven inserts no longer violate NOT NULL.
/// It is idempotent and a no-op on fresh databases that already have the
/// `languages` column.
class ExportHistoryLanguagesMigration extends Migration {
  final ILoggingService _logger;

  ExportHistoryLanguagesMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'export_history_languages_from_language_code';

  @override
  String get description =>
      'Backfill export_history.languages from legacy language_code column';

  /// Runs after the other column-adding migrations.
  @override
  int get priority => 200;

  Future<bool> _tableExists() async {
    final rows = await DatabaseService.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='export_history'",
    );
    return rows.isNotEmpty;
  }

  Future<Set<String>> _columns() async {
    final rows =
        await DatabaseService.rawQuery('PRAGMA table_info(export_history)');
    return rows.map((r) => r['name'] as String).toSet();
  }

  @override
  Future<bool> isApplied() async {
    if (!await _tableExists()) return true; // nothing to migrate
    final cols = await _columns();
    // Done once the new column exists and the legacy column is gone.
    return cols.contains('languages') && !cols.contains('language_code');
  }

  @override
  Future<bool> execute() async {
    try {
      if (!await _tableExists()) return false;

      final cols = await _columns();
      final hasLanguages = cols.contains('languages');
      final hasLanguageCode = cols.contains('language_code');

      // Fresh schema already correct, or an unrecognized shape — leave it.
      if (!hasLanguageCode) return false;

      // 1) Add the new column if missing (nullable add; backfilled below).
      if (!hasLanguages) {
        await DatabaseService.execute(
          'ALTER TABLE export_history ADD COLUMN languages TEXT',
        );
      }

      // 2) Backfill: wrap the single legacy code in a one-element JSON array.
      await DatabaseService.execute(
        "UPDATE export_history "
        "SET languages = '[\"' || language_code || '\"]' "
        "WHERE (languages IS NULL OR languages = '') "
        "AND language_code IS NOT NULL AND TRIM(language_code) <> ''",
      );
      // Any rows without a usable code get an empty JSON array (never null).
      await DatabaseService.execute(
        "UPDATE export_history SET languages = '[]' "
        "WHERE languages IS NULL OR languages = ''",
      );

      // 3) Drop any legacy index that references language_code (e.g.
      //    idx_export_project_lang from the pre-unified schema). SQLite refuses
      //    to drop a column while an index still depends on it, so this must
      //    happen before the column drop below. The PK autoindex has a NULL
      //    `sql` and is excluded by the LIKE filter.
      final dependentIndexes = await DatabaseService.rawQuery(
        "SELECT name FROM sqlite_master "
        "WHERE type='index' AND tbl_name='export_history' "
        "AND sql LIKE '%language_code%'",
      );
      for (final row in dependentIndexes) {
        final name = row['name'] as String?;
        if (name != null) {
          await DatabaseService.execute('DROP INDEX IF EXISTS $name');
        }
      }

      // 4) Drop the obsolete NOT NULL column so model-driven inserts (which
      //    omit it) no longer fail. Non-fatal if the SQLite build is too old
      //    to support DROP COLUMN — the backfill already fixed reads, and
      //    isApplied() keeps this migration pending for a later retry.
      try {
        await DatabaseService.execute(
          'ALTER TABLE export_history DROP COLUMN language_code',
        );
      } catch (e) {
        _logger.warning(
          'export_history.language_code not dropped (SQLite may predate '
          'DROP COLUMN); reads are fixed but inserts may still fail',
          {'error': e.toString()},
        );
      }

      _logger.info('Migrated export_history.language_code -> languages');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to migrate export_history languages column',
        e,
        stackTrace,
      );
      return false;
    }
  }
}
