import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to add project_type and source_language_code columns to projects table.
///
/// This enables distinguishing between mod translation projects and game translation projects.
/// - project_type: 'mod' (default) or 'game'
/// - source_language_code: The language code of the source pack for game translations (e.g., 'en', 'fr')
class ProjectTypeMigration extends Migration {
  final ILoggingService _logger;

  ProjectTypeMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'project_type_columns';

  @override
  String get description => 'Add project_type and source_language_code columns to projects';

  @override
  int get priority => 91;

  @override
  Future<bool> isApplied() async {
    // Both columns must exist: the two ALTER statements auto-commit
    // independently, so a crash between them leaves only the first column.
    // Checking a single column would mark the half-applied state as done
    // forever (permanent schema divergence).
    final columns = await _existingColumns();
    return columns.contains('project_type') &&
        columns.contains('source_language_code');
  }

  @override
  Future<bool> execute() async {
    try {
      // Check-and-add each column independently. This is idempotent and also
      // repairs databases left half-applied by a crash between the two
      // auto-committed ALTER statements.
      final columns = await _existingColumns();
      var changed = false;

      // project_type column with default 'mod' for existing projects
      if (!columns.contains('project_type')) {
        await DatabaseService.execute('''
          ALTER TABLE projects
          ADD COLUMN project_type TEXT NOT NULL DEFAULT 'mod'
        ''');
        changed = true;
      }

      // source_language_code column (nullable, only used for game translations)
      if (!columns.contains('source_language_code')) {
        await DatabaseService.execute('''
          ALTER TABLE projects
          ADD COLUMN source_language_code TEXT
        ''');
        changed = true;
      }

      if (changed) {
        _logger.info(
            'Ensured project_type and source_language_code columns on projects');
      }
      return changed;
    } catch (e, stackTrace) {
      _logger.error('Failed to add project type columns', e, stackTrace);
      // Non-fatal: feature will be unavailable but app still works
      return false;
    }
  }

  Future<Set<String>> _existingColumns() async {
    final columns = await DatabaseService.database.rawQuery(
      'PRAGMA table_info(projects)',
    );
    return columns.map((col) => col['name'] as String).toSet();
  }
}
