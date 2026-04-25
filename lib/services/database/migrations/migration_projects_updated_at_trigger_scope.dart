import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Recreate `trg_projects_updated_at` with a column-restricted `AFTER UPDATE
/// OF` clause so it only fires when *content* columns change.
///
/// Context: the original trigger fired on every UPDATE to `projects`, then
/// stamped `updated_at = NOW` whenever the caller had preserved the old
/// value. That is correct for content edits (and is the signal the Projects
/// screen reads via `isModifiedSinceLastExport` to flag "Export outdated"),
/// but it is wrong for purely-bookkeeping updates such as recording a Steam
/// Workshop publish (`published_steam_id` / `published_at`) or toggling the
/// mod-update-impact flag (`has_mod_update_impact`). Those operations
/// preserve `updated_at` in Dart, the trigger fires nonetheless, and every
/// project ends up flagged as "Export outdated" right after a publish run.
///
/// SQLite supports `AFTER UPDATE OF col1, col2, ...` — the trigger only
/// fires when one of those columns is in the `SET` clause. We list the
/// columns that genuinely represent project-content changes and leave the
/// publish/flag columns out of the list.
class ProjectsUpdatedAtTriggerScopeMigration extends Migration {
  final ILoggingService _logger;

  ProjectsUpdatedAtTriggerScopeMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'projects_updated_at_trigger_scope';

  @override
  String get description =>
      'Restrict trg_projects_updated_at to content columns so publish/flag '
      'updates do not bump projects.updated_at';

  @override
  int get priority => 150;

  @override
  Future<bool> execute() async {
    try {
      _logger.info('Recreating trg_projects_updated_at with column scope');

      await DatabaseService.execute(
          'DROP TRIGGER IF EXISTS trg_projects_updated_at');

      await DatabaseService.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_projects_updated_at
        AFTER UPDATE OF
            name, mod_steam_id, mod_version, game_installation_id,
            source_file_path, output_file_path, last_update_check,
            source_mod_updated, batch_size, parallel_batches,
            custom_prompt, completed_at, metadata,
            project_type, source_language_code
        ON projects
        WHEN NEW.updated_at = OLD.updated_at
        BEGIN
            UPDATE projects SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
        END
      ''');

      _logger.info('Trigger recreated with column scope');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to recreate trg_projects_updated_at with column scope',
        e,
        stackTrace,
      );
      rethrow;
    }
  }
}
