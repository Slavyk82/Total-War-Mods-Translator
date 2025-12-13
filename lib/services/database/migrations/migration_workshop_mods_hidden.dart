import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to ensure is_hidden column exists on workshop_mods table.
///
/// This column allows users to hide mods from the main list.
class WorkshopModsHiddenMigration extends Migration {
  @override
  String get id => 'workshop_mods_hidden_column';

  @override
  String get description => 'Add is_hidden column to workshop_mods';

  @override
  int get priority => 60;

  @override
  Future<bool> isApplied() async {
    final columns = await DatabaseService.database.rawQuery(
      "PRAGMA table_info(workshop_mods)"
    );
    return columns.any((col) => col['name'] == 'is_hidden');
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE workshop_mods
        ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0
      ''');
      logging.info('Added is_hidden column to workshop_mods');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add is_hidden column', e, stackTrace);
      // Non-fatal: hiding feature will be unavailable but app still works
      return false;
    }
  }
}
