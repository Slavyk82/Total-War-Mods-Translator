import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add published_at column to projects table.
///
/// This column stores the Unix timestamp of when the translation pack
/// was published to the Steam Workshop.
class PublishedAtMigration extends Migration {
  @override
  String get id => 'published_at_column';

  @override
  String get description => 'Add published_at column to projects';

  @override
  int get priority => 93;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(projects)"
    );
    return columns.any((col) => col['name'] == 'published_at');
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
        ADD COLUMN published_at INTEGER
      ''');
      logging.info('Added published_at column to projects');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add published_at column', e, stackTrace);
      return false;
    }
  }
}
