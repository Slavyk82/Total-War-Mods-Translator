import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to extend `trg_update_project_language_progress` so it also
/// bumps `projects.updated_at` whenever a translation_versions UPDATE
/// changes the status.
///
/// Without this cascade, per-row translation edits leave `projects.updated_at`
/// stale — which in turn breaks the Projects screen's "Export outdated" quick
/// filter (`project.updatedAt > lastPackExport.exportedAt + 60`). Bulk methods
/// on `TranslationVersionRepository` maintain the same invariant explicitly
/// since they drop this trigger for performance.
class CascadeProjectUpdatedAtMigration extends Migration {
  final ILoggingService _logger;

  CascadeProjectUpdatedAtMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'cascade_project_updated_at_on_version_status_change';

  @override
  String get description =>
      'Extend trg_update_project_language_progress to bump projects.updated_at';

  @override
  int get priority => 140;

  @override
  Future<bool> execute() async {
    try {
      _logger.info(
          'Recreating trg_update_project_language_progress with projects cascade');

      await DatabaseService.execute(
          'DROP TRIGGER IF EXISTS trg_update_project_language_progress');

      await DatabaseService.execute('''
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
      ''');

      _logger.info('Trigger recreated with projects cascade');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to recreate progress trigger', e, stackTrace);
      rethrow;
    }
  }
}
