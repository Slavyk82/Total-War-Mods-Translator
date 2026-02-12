import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add published_steam_id column to projects table.
///
/// This column stores the Steam Workshop ID of the published translation pack,
/// distinct from mod_steam_id (the source mod being translated).
class PublishedSteamIdMigration extends Migration {
  @override
  String get id => 'published_steam_id_column';

  @override
  String get description => 'Add published_steam_id column to projects';

  @override
  int get priority => 92;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(projects)"
    );
    return columns.any((col) => col['name'] == 'published_steam_id');
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
        ADD COLUMN published_steam_id TEXT
      ''');
      logging.info('Added published_steam_id column to projects');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add published_steam_id column', e, stackTrace);
      return false;
    }
  }
}
