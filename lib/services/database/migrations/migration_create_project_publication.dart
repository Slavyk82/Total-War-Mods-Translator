import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Create the `project_publication` table and backfill it from the legacy
/// `projects.published_steam_id` / `published_at` columns.
///
/// Published Workshop ids for translations live per (project, language) in
/// this table — distinct from `projects.mod_steam_id` (the source mod) and
/// from the now-vestigial flat `projects.published_steam_id` column. The
/// backfill resolves each legacy id to the project's target language,
/// preferring `fr` when present, so installs that wrote ids to the flat
/// column keep their data.
class CreateProjectPublicationMigration extends Migration {
  final ILoggingService _logger;

  CreateProjectPublicationMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'create_project_publication';

  @override
  String get description =>
      'Create project_publication table and backfill from legacy '
      'projects.published_steam_id';

  @override
  int get priority => 96;

  @override
  Future<bool> isApplied() async {
    final rows = await DatabaseService.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='project_publication'",
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS project_publication (
          project_id TEXT NOT NULL,
          language_code TEXT NOT NULL,
          steam_id TEXT,
          published_at INTEGER,
          PRIMARY KEY (project_id, language_code)
        )
      ''');

      final projectCols = await DatabaseService.database
          .rawQuery('PRAGMA table_info(projects)');
      final hasLegacy =
          projectCols.any((c) => c['name'] == 'published_steam_id');
      if (hasLegacy) {
        await DatabaseService.execute('''
          INSERT OR IGNORE INTO project_publication
            (project_id, language_code, steam_id, published_at)
          SELECT
            p.id,
            COALESCE(
              (SELECT l.code
                 FROM project_languages pl
                 JOIN languages l ON l.id = pl.language_id
                WHERE pl.project_id = p.id
                ORDER BY (l.code = 'fr') DESC, pl.created_at ASC
                LIMIT 1),
              'fr'),
            p.published_steam_id,
            p.published_at
          FROM projects p
          WHERE p.published_steam_id IS NOT NULL
            AND p.published_steam_id <> ''
        ''');
      }

      _logger.info('Ensured project_publication table (with legacy backfill)');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to create project_publication', e, stackTrace);
      return false;
    }
  }
}
