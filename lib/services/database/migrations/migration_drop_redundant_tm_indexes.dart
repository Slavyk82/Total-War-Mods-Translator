import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Drops two redundant indexes on `translation_memory`.
///
/// Both are covered by `UNIQUE(source_hash, target_language_id)` (which SQLite
/// backs with an auto-index): the leftmost prefix satisfies lookups on
/// `source_hash` alone, and the full pair satisfies composite lookups. The
/// extra hand-rolled indexes only slowed writes and wasted disk.
class DropRedundantTmIndexesMigration extends Migration {
  final ILoggingService _logger;

  DropRedundantTmIndexesMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'drop_redundant_tm_indexes';

  @override
  String get description =>
      'Drop redundant indexes (idx_tm_hash_lang, idx_tm_source_hash) covered by UNIQUE auto-index';

  @override
  int get priority => 16; // Right after PerformanceIndexesV2Migration (15).

  @override
  Future<bool> execute() async {
    try {
      await DatabaseService.execute(
        'DROP INDEX IF EXISTS idx_tm_hash_lang',
      );
      await DatabaseService.execute(
        'DROP INDEX IF EXISTS idx_tm_source_hash',
      );
      _logger.info('Redundant TM indexes dropped (if present)');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to drop redundant TM indexes', e, stackTrace);
      return false;
    }
  }
}
