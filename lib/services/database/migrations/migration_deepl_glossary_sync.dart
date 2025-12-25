import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add DeepL glossary synchronization support.
///
/// Creates a table to track the mapping between TWMT glossaries
/// and DeepL glossaries on DeepL's servers.
///
/// This enables:
/// - Automatic sync of glossaries to DeepL before translation
/// - Tracking of sync status and timestamps
/// - Proper cleanup when glossaries are deleted
class DeepLGlossarySyncMigration extends Migration {
  @override
  String get id => 'deepl_glossary_sync';

  @override
  String get description => 'Add DeepL glossary synchronization support';

  @override
  int get priority => 77;

  @override
  Future<bool> isApplied() async {
    // Check if the table exists
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM sqlite_master WHERE type='table' AND name='deepl_glossary_mappings'"
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      // Create the mapping table
      await DatabaseService.execute('''
        CREATE TABLE IF NOT EXISTS deepl_glossary_mappings (
          id TEXT PRIMARY KEY,
          twmt_glossary_id TEXT NOT NULL,
          source_language_code TEXT NOT NULL,
          target_language_code TEXT NOT NULL,
          deepl_glossary_id TEXT NOT NULL,
          deepl_glossary_name TEXT NOT NULL,
          entry_count INTEGER NOT NULL DEFAULT 0,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          synced_at INTEGER NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          UNIQUE(twmt_glossary_id, source_language_code, target_language_code),
          FOREIGN KEY (twmt_glossary_id) REFERENCES glossaries(id) ON DELETE CASCADE
        )
      ''');

      // Create index for faster lookups
      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_deepl_mappings_glossary
        ON deepl_glossary_mappings(twmt_glossary_id)
      ''');

      await DatabaseService.execute('''
        CREATE INDEX IF NOT EXISTS idx_deepl_mappings_deepl_id
        ON deepl_glossary_mappings(deepl_glossary_id)
      ''');

      logging.info('DeepL glossary sync table created successfully');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to create DeepL glossary sync table', e, stackTrace);
      return false;
    }
  }
}
