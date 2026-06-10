import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to drop the broken `v_translations_needing_review` view.
///
/// Legacy schema.sql created this view referencing `tv.confidence_score`,
/// a column that does not exist on `translation_versions` (it only exists
/// on `translation_view_cache`). SQLite does not validate view bodies at
/// CREATE time, so the view installed fine — but every full schema
/// re-parse fails on it, which makes unrelated `ALTER TABLE ... RENAME` /
/// `DROP COLUMN` statements error out (see the `legacy_alter_table`
/// workarounds in `GlossaryGameCodePartialMigration` and
/// `GlossaryMigrationService`).
///
/// No production code queries the view, so the fix is to drop it. The
/// definition has also been removed from schema.sql so fresh installs never
/// create it.
class DropBrokenReviewViewMigration extends Migration {
  final ILoggingService _logger;

  DropBrokenReviewViewMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  static const String _viewName = 'v_translations_needing_review';

  @override
  String get id => 'drop_broken_needing_review_view';

  @override
  String get description =>
      'Drop broken v_translations_needing_review view (references '
      'non-existent translation_versions.confidence_score)';

  @override
  int get priority => 220;

  @override
  Future<bool> isApplied() async {
    final rows = await DatabaseService.database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'view' AND name = ?",
      [_viewName],
    );
    return rows.isEmpty;
  }

  @override
  Future<bool> execute() async {
    try {
      if (await isApplied()) {
        return false; // View already gone
      }

      // DROP VIEW does not re-parse the view body, so it works even though
      // the view itself cannot be compiled.
      await DatabaseService.execute('DROP VIEW IF EXISTS $_viewName');
      _logger.info('Dropped broken $_viewName view');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to drop broken $_viewName view', e, stackTrace);
      return false;
    }
  }
}
