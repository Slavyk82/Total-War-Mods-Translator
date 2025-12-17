import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add project_type and source_language_code columns to projects table.
///
/// This enables distinguishing between mod translation projects and game translation projects.
/// - project_type: 'mod' (default) or 'game'
/// - source_language_code: The language code of the source pack for game translations (e.g., 'en', 'fr')
class ProjectTypeMigration extends Migration {
  @override
  String get id => 'project_type_columns';

  @override
  String get description => 'Add project_type and source_language_code columns to projects';

  @override
  int get priority => 91;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(projects)"
    );
    return columns.any((col) => col['name'] == 'project_type');
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      // Add project_type column with default 'mod' for existing projects
      await DatabaseService.execute('''
        ALTER TABLE projects
        ADD COLUMN project_type TEXT NOT NULL DEFAULT 'mod'
      ''');
      logging.info('Added project_type column to projects');

      // Add source_language_code column (nullable, only used for game translations)
      await DatabaseService.execute('''
        ALTER TABLE projects
        ADD COLUMN source_language_code TEXT
      ''');
      logging.info('Added source_language_code column to projects');

      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add project type columns', e, stackTrace);
      // Non-fatal: feature will be unavailable but app still works
      return false;
    }
  }
}
