import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure performance indexes exist on the database.
///
/// These indexes were identified through database analysis as high-priority
/// optimizations for common query patterns. Uses CREATE INDEX IF NOT EXISTS
/// so it's safe to run multiple times.
class PerformanceIndexesMigration extends Migration {
  @override
  String get id => 'performance_indexes';

  @override
  String get description => 'Create performance optimization indexes';

  @override
  int get priority => 10; // Run early

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;
    logging.debug('Ensuring performance indexes exist');

    const performanceIndexes = [
      // Index on translation_version_history.version_id for FK lookups
      '''CREATE INDEX IF NOT EXISTS idx_translation_version_history_version
         ON translation_version_history(version_id)''',
      // Composite index for common JOIN pattern between units and versions
      '''CREATE INDEX IF NOT EXISTS idx_translation_versions_unit_proj_lang
         ON translation_versions(unit_id, project_language_id)''',
    ];

    try {
      for (final indexSql in performanceIndexes) {
        await DatabaseService.execute(indexSql);
      }
      logging.info('Performance indexes verified/created successfully');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create performance indexes', e, stackTrace);
      // Non-fatal: indexes are optimization, not required for functionality
      return false;
    }
  }
}
