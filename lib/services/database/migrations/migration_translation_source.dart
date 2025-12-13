import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure translation_source column exists in translation_versions.
///
/// This column tracks the source of each translation (manual, tm_exact, tm_fuzzy, llm).
class TranslationSourceMigration extends Migration {
  @override
  String get id => 'translation_source_column';

  @override
  String get description => 'Add translation_source column to translation_versions';

  @override
  int get priority => 30;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(translation_versions)"
    );
    return columns.any((col) => col['name'] == 'translation_source');
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE translation_versions
        ADD COLUMN translation_source TEXT DEFAULT 'unknown'
      ''');
      logging.info('Added translation_source column to translation_versions');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add translation_source column', e, stackTrace);
      // Non-fatal: display will fall back to confidence-based detection
      return false;
    }
  }
}
