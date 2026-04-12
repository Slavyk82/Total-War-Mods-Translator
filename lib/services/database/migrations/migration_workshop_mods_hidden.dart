import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to ensure is_hidden column exists on workshop_mods table.
///
/// This column allows users to hide mods from the main list.
class WorkshopModsHiddenMigration extends Migration {
  final ILoggingService _logger;

  WorkshopModsHiddenMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

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
    try {
      if (await isApplied()) {
        return false; // Already applied
      }

      await DatabaseService.execute('''
        ALTER TABLE workshop_mods
        ADD COLUMN is_hidden INTEGER NOT NULL DEFAULT 0
      ''');
      _logger.info('Added is_hidden column to workshop_mods');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to add is_hidden column', e, stackTrace);
      // Non-fatal: hiding feature will be unavailable but app still works
      return false;
    }
  }
}
