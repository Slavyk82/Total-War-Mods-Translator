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

  DeepSeekChatRestoreMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'deepseek_chat_restore';

  @override
  String get description =>
      'Restore deepseek-chat (V3.2) as an available DeepSeek model';

  @override
  int get priority => 190;

  @override
  Future<bool> isApplied() async {
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM llm_provider_models "
      "WHERE model_id = 'deepseek-chat' AND is_archived = 0 AND is_enabled = 1",
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

      _logger.info('DeepSeek deepseek-chat (V3.2) restored as available model');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to restore deepseek-chat', e, stackTrace);
      return false;
    }
  }
}
