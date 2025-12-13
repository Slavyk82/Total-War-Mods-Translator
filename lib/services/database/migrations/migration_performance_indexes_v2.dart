import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add additional performance indexes to the database.
///
/// These indexes optimize common query patterns identified through usage analysis:
/// - Translation unit queries filtered by project and obsolete status
/// - Translation version queries filtered by status and language
/// - Translation memory lookups by source hash
/// - Glossary entry lookups by glossary and source term
///
/// Uses CREATE INDEX IF NOT EXISTS so it's safe to run multiple times.
class PerformanceIndexesV2Migration extends Migration {
  @override
  String get id => 'performance_indexes_v2';

  @override
  String get description => 'Create additional performance optimization indexes';

  @override
  int get priority => 15; // Run after initial performance indexes (priority 10)

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;
    logging.debug('Ensuring additional performance indexes exist');

    const performanceIndexes = [
      // Composite index for filtering translation units by project and obsolete status
      // Used in: Translation editor queries, project statistics
      '''CREATE INDEX IF NOT EXISTS idx_translation_units_project_obsolete
         ON translation_units(project_id, is_obsolete)''',

      // Composite index for translation version status queries
      // Used in: Progress statistics, filtering by completion status
      '''CREATE INDEX IF NOT EXISTS idx_translation_versions_status
         ON translation_versions(project_language_id, status)''',

      // Index for translation memory source hash lookups
      // Used in: TM matching during translation
      '''CREATE INDEX IF NOT EXISTS idx_tm_source_hash
         ON translation_memory(source_hash)''',

      // Composite index for glossary entry lookups
      // Used in: Glossary term matching during translation
      '''CREATE INDEX IF NOT EXISTS idx_glossary_entries_source_term
         ON glossary_entries(glossary_id, source_term)''',
    ];

    try {
      for (final indexSql in performanceIndexes) {
        await DatabaseService.execute(indexSql);
      }
      logging.info('Additional performance indexes verified/created successfully');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create additional performance indexes', e, stackTrace);
      // Non-fatal: indexes are optimization, not required for functionality
      return false;
    }
  }
}
