import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure mod_update_analysis_cache table exists.
///
/// This allows existing databases to get the new caching functionality
/// without requiring a full database re-creation.
class ModUpdateCacheMigration extends Migration {
  @override
  String get id => 'mod_update_analysis_cache';

  @override
  String get description => 'Create mod update analysis cache table';

  @override
  int get priority => 20;

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS mod_update_analysis_cache (
          id TEXT PRIMARY KEY,
          project_id TEXT NOT NULL,
          pack_file_path TEXT NOT NULL,
          file_last_modified INTEGER NOT NULL,
          new_units_count INTEGER NOT NULL DEFAULT 0,
          removed_units_count INTEGER NOT NULL DEFAULT 0,
          modified_units_count INTEGER NOT NULL DEFAULT 0,
          total_pack_units INTEGER NOT NULL DEFAULT 0,
          total_project_units INTEGER NOT NULL DEFAULT 0,
          analyzed_at INTEGER NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE CASCADE,
          UNIQUE(project_id, pack_file_path)
        )
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_mod_update_analysis_cache_project
        ON mod_update_analysis_cache(project_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_mod_update_analysis_cache_pack_path
        ON mod_update_analysis_cache(pack_file_path)
      ''');

      logging.debug('mod_update_analysis_cache table verified/created');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create mod_update_analysis_cache table', e, stackTrace);
      // Non-fatal: caching is optimization, not required for functionality
      return false;
    }
  }
}
