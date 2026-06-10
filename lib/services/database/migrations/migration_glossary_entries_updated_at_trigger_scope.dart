import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Recreate `trg_glossary_entries_updated_at` with a column-restricted
/// `AFTER UPDATE OF` clause so it only fires when *content* columns change.
///
/// Context: the original trigger fired on every UPDATE to `glossary_entries`
/// and stamped `updated_at = NOW` whenever the caller preserved the old value.
/// That is correct for content edits (the signal `doesMappingNeedResync` reads
/// via `MAX(updated_at) > mapping.synced_at` to rebuild the DeepL glossary),
/// but it is wrong for `incrementUsageCount`, which bumps only `usage_count` on
/// the hot translation path. Every matched glossary term then looked like a
/// content edit and forced a needless DeepL glossary rebuild (API churn and
/// limited-slot consumption).
///
/// SQLite supports `AFTER UPDATE OF col1, col2, ...` — the trigger only fires
/// when one of those columns is in the `SET` clause. We list the columns that
/// genuinely represent glossary-entry content and leave `usage_count` out, so
/// usage statistics no longer count as a content change. Mirrors
/// [ProjectsUpdatedAtTriggerScopeMigration].
class GlossaryEntriesUpdatedAtTriggerScopeMigration extends Migration {
  final ILoggingService _logger;

  GlossaryEntriesUpdatedAtTriggerScopeMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'glossary_entries_updated_at_trigger_scope';

  @override
  String get description =>
      'Restrict trg_glossary_entries_updated_at to content columns so usage '
      'bumps do not force a DeepL glossary resync';

  @override
  int get priority => 240;

  @override
  Future<bool> execute() async {
    try {
      _logger.info('Recreating trg_glossary_entries_updated_at with column scope');

      await DatabaseService.execute(
          'DROP TRIGGER IF EXISTS trg_glossary_entries_updated_at');

      await DatabaseService.execute('''
        CREATE TRIGGER IF NOT EXISTS trg_glossary_entries_updated_at
        AFTER UPDATE OF
            target_language_code, source_term, target_term,
            definition, notes, is_forbidden, case_sensitive
        ON glossary_entries
        WHEN NEW.updated_at = OLD.updated_at
        BEGIN
            UPDATE glossary_entries SET updated_at = strftime('%s', 'now') WHERE id = NEW.id;
        END
      ''');

      _logger.info('Trigger recreated with column scope');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to recreate trg_glossary_entries_updated_at with column scope',
        e,
        stackTrace,
      );
      rethrow;
    }
  }
}
