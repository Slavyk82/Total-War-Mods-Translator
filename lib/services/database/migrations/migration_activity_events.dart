import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to create the activity_events table for the Home dashboard feed.
///
/// Stores a stream of typed domain events (project created, compilation
/// finished, translation batch completed, etc.). Indexed on `timestamp`
/// (for the global recent-feed) and on `(game_code, timestamp)` (for
/// per-game filtering).
class ActivityEventsMigration extends Migration {
  final ILoggingService _logger;

  ActivityEventsMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'activity_events_table';

  @override
  String get description =>
      'Create activity_events table and indexes for the Home dashboard feed';

  @override
  int get priority => 95;

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS activity_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          timestamp INTEGER NOT NULL,
          project_id TEXT,
          game_code TEXT,
          payload TEXT NOT NULL,
          FOREIGN KEY (project_id) REFERENCES projects(id) ON DELETE SET NULL
        )
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_activity_events_ts
        ON activity_events(timestamp DESC)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_activity_events_game
        ON activity_events(game_code, timestamp DESC)
      ''');

      _logger.debug('activity_events table verified/created');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to create activity_events table', e, stackTrace);
      return false;
    }
  }
}
