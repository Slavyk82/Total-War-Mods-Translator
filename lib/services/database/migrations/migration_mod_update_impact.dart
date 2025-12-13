import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure has_mod_update_impact column exists on projects table.
///
/// This column flags projects that were impacted by a mod update,
/// allowing users to filter for projects that need attention after mod updates.
class ModUpdateImpactMigration extends Migration {
  @override
  String get id => 'mod_update_impact_column';

  @override
  String get description => 'Add has_mod_update_impact column to projects';

  @override
  int get priority => 90;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(projects)"
    );
    return columns.any((col) => col['name'] == 'has_mod_update_impact');
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE projects
        ADD COLUMN has_mod_update_impact INTEGER NOT NULL DEFAULT 0
      ''');
      logging.info('Added has_mod_update_impact column to projects');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add has_mod_update_impact column', e, stackTrace);
      // Non-fatal: feature will be unavailable but app still works
      return false;
    }
  }
}
