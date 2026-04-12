import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to ensure translation_source column exists in translation_versions.
///
/// This column tracks the source of each translation (manual, tm_exact, tm_fuzzy, llm).
class TranslationSourceMigration extends Migration {
  final ILoggingService _logger;

  TranslationSourceMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

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
    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE translation_versions
        ADD COLUMN translation_source TEXT DEFAULT 'unknown'
      ''');
      _logger.info('Added translation_source column to translation_versions');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to add translation_source column', e, stackTrace);
      // Non-fatal: display will fall back to confidence-based detection
      return false;
    }
  }
}
