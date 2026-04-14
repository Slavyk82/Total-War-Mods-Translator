import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to add published_steam_id and published_at columns to compilations table.
///
/// These columns store the Workshop publish state for compilations,
/// mirroring what projects already have.
class CompilationPublishFieldsMigration extends Migration {
  final ILoggingService _logger;

  CompilationPublishFieldsMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'compilation_publish_fields';

  @override
  String get description => 'Add published_steam_id and published_at columns to compilations';

  @override
  int get priority => 94;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(compilations)"
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
        ALTER TABLE compilations
        ADD COLUMN published_steam_id TEXT
      ''');
      await DatabaseService.execute('''
        ALTER TABLE compilations
        ADD COLUMN published_at INTEGER
      ''');
      _logger.info('Added published_steam_id and published_at columns to compilations');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to add compilation publish fields', e, stackTrace);
      return false;
    }
  }
}
