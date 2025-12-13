import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure compilation tables exist for existing databases.
///
/// Creates compilations and compilation_projects tables for
/// grouping multiple projects into a single pack file.
class CompilationTablesMigration extends Migration {
  @override
  String get id => 'compilation_tables';

  @override
  String get description => 'Create compilation tables for pack file grouping';

  @override
  int get priority => 40;

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      // Create compilations table
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS compilations (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          prefix TEXT NOT NULL DEFAULT '!!!!!!!!!!_fr_compilation_twmt_',
          pack_name TEXT NOT NULL,
          game_installation_id TEXT NOT NULL,
          last_output_path TEXT,
          last_generated_at INTEGER,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          FOREIGN KEY (game_installation_id) REFERENCES game_installations(id) ON DELETE RESTRICT,
          CHECK (created_at <= updated_at)
        )
      ''');

      // Create compilation_projects junction table
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS compilation_projects (
          id TEXT PRIMARY KEY,
          compilation_id TEXT NOT NULL,
          project_id TEXT NOT NULL,
          sort_order INTEGER NOT NULL DEFAULT 0,
          added_at INTEGER NOT NULL,
          FOREIGN KEY (compilation_id) REFERENCES compilations(id) ON DELETE CASCADE,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
          UNIQUE(compilation_id, project_id)
        )
      ''');

      // Create indexes
      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_compilations_game
        ON compilations(game_installation_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_compilation_projects_compilation
        ON compilation_projects(compilation_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_compilation_projects_project
        ON compilation_projects(project_id)
      ''');

      // Add language_id column if it doesn't exist
      await _ensureLanguageIdColumn(logging);

      logging.debug('Compilation tables verified/created');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create compilation tables', e, stackTrace);
      // Non-fatal: feature will be unavailable but app still works
      return false;
    }
  }

  Future<void> _ensureLanguageIdColumn(LoggingService logging) async {
    final compilationColumns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(compilations)"
    );
    final hasLanguageIdColumn = compilationColumns.any((col) => col['name'] == 'language_id');

    if (!hasLanguageIdColumn) {
      await DatabaseService.execute('''
        ALTER TABLE compilations ADD COLUMN language_id TEXT
          REFERENCES languages(id) ON DELETE SET NULL
      ''');
      logging.info('Added language_id column to compilations');
    }
  }
}
