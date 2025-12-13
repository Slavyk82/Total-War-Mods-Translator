import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure is_custom column exists on languages table.
///
/// This column allows users to add custom languages that can be deleted,
/// while system languages (is_custom = 0) are read-only.
class LanguagesCustomMigration extends Migration {
  @override
  String get id => 'languages_custom_column';

  @override
  String get description => 'Add is_custom column to languages table';

  @override
  int get priority => 80;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(languages)"
    );
    return columns.any((col) => col['name'] == 'is_custom');
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE languages
        ADD COLUMN is_custom INTEGER NOT NULL DEFAULT 0
      ''');
      logging.info('Added is_custom column to languages');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add is_custom column to languages', e, stackTrace);
      // Non-fatal: custom languages feature will be unavailable but app still works
      return false;
    }
  }
}
