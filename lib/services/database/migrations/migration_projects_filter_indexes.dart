import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Adds filter indexes for `ProjectRepository` queries that filter by
/// `project_type` and/or `has_mod_update_impact`.
///
/// `idx_projects_impact` is a partial index — only rows where the flag is
/// actually set are indexed, which keeps it tiny while still accelerating
/// `countWithModUpdateImpact`.
///
/// Priority 120 — must run after both `ModUpdateImpactMigration` (90) and
/// `ProjectTypeMigration` (91), which add the indexed columns via
/// `ALTER TABLE ADD COLUMN`. Indexing a missing column would fail.
class ProjectsFilterIndexesMigration extends Migration {
  final ILoggingService _logger;

  ProjectsFilterIndexesMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'projects_filter_indexes';

  @override
  String get description =>
      'Add indexes on projects(project_type) and partial index on has_mod_update_impact';

  @override
  int get priority => 120;

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_type ON projects(project_type)',
      );
      await DatabaseService.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_game_type '
        'ON projects(game_installation_id, project_type)',
      );
      await DatabaseService.execute(
        'CREATE INDEX IF NOT EXISTS idx_projects_impact '
        'ON projects(game_installation_id, has_mod_update_impact) '
        'WHERE has_mod_update_impact = 1',
      );
      _logger.info('Projects filter indexes verified/created');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to create projects filter indexes', e, stackTrace);
      return false;
    }
  }
}
