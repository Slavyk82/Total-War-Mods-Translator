import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to add published_steam_id column to projects table.
///
/// This column stores the Steam Workshop ID of the published translation pack,
/// distinct from mod_steam_id (the source mod being translated).
class PublishedSteamIdMigration extends Migration {
  final ILoggingService _logger;

  PublishedSteamIdMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

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
    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE projects
        ADD COLUMN published_steam_id TEXT
      ''');
      _logger.info('Added published_steam_id column to projects');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to add published_steam_id column', e, stackTrace);
      return false;
    }
  }
}
