import 'package:uuid/uuid.dart';

import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration that restores `deepseek-chat` (DeepSeek V3.2) as an available
/// model alongside the V4 family seeded by [DeepSeekV4ModelsMigration].
///
/// The earlier v4 migration archived `deepseek-chat`; this one un-archives it
/// (or inserts the row if missing) so it shows up in the model picker again.
/// `deepseek-v4-flash` remains the provider default — only the row's enabled
/// / archived flags are touched here.
class DeepSeekChatRestoreMigration extends Migration {
  final ILoggingService _logger;
  final Uuid _uuid = const Uuid();

  DeepSeekChatRestoreMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'deepseek_chat_restore';

  /// Settings marker key recorded once this migration has successfully run.
  ///
  /// The migration runner re-evaluates [isApplied] on every startup with no
  /// shared ledger, so a one-shot restore must persist its own "already ran"
  /// record (same settings-marker mechanism as [FixCacheTriggersMigration]).
  static const String _markerKey = 'migration_deepseek_chat_restore_applied';

  @override
  String get description =>
      'Restore deepseek-chat (V3.2) as an available DeepSeek model';

  @override
  int get priority => 190;

  @override
  Future<bool> isApplied() async {
    // Marker present → the restore already ran on this database.
    final marker = await DatabaseService.database.rawQuery(
      'SELECT COUNT(*) as cnt FROM settings WHERE key = ?',
      [_markerKey],
    );
    if (((marker.first['cnt'] as int?) ?? 0) > 0) return true;

    // No marker (database predates it): the restore is only needed when the
    // row is missing or still archived by the v4 migration. An existing
    // non-archived row means the restore already happened (or was never
    // needed). Deliberately do NOT check is_enabled: the user disabling the
    // model in Settings must not retrigger the restore on the next startup.
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM llm_provider_models "
      "WHERE model_id = 'deepseek-chat' AND is_archived = 0",
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    try {
      // Insert the row if it was never seeded (fresh install on a build before
      // schema.sql was updated, or DB created from a future schema without
      // the legacy row).
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_deepseek_chat', 'deepseek', 'deepseek-chat', 'DeepSeek V3.2', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      // Un-archive the existing row left behind by the v4 migration.
      await DatabaseService.execute('''
        UPDATE llm_provider_models
        SET is_enabled = 1,
            is_archived = 0,
            updated_at = strftime('%s', 'now')
        WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'
      ''');

      // Record the marker so this one-shot restore never runs again — in
      // particular it must never override a later user disable or archival.
      await _markApplied();

      _logger.info('DeepSeek deepseek-chat (V3.2) restored as available model');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to restore deepseek-chat', e, stackTrace);
      return false;
    }
  }

  /// Persist the settings marker row indicating the migration has run.
  Future<void> _markApplied() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await DatabaseService.rawInsert(
      '''
      INSERT OR REPLACE INTO settings (id, key, value, value_type, updated_at)
      VALUES (
        COALESCE((SELECT id FROM settings WHERE key = ?), ?),
        ?, ?, ?, ?
      )
      ''',
      [_markerKey, _uuid.v4(), _markerKey, '1', 'boolean', now],
    );
  }
}
