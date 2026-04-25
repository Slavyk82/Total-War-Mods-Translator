import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to upgrade DeepSeek to v4 models.
///
/// API Documentation: https://api-docs.deepseek.com/
/// Replaces the legacy `deepseek-chat` (V3.2) entry with the v4 family:
///   - deepseek-v4-flash (default) — fast, cost-efficient
///   - deepseek-v4-pro             — higher quality, larger reasoning budget
/// Both models share a 1M context window and up to 384K max output tokens.
///
/// The legacy `deepseek-chat` model row is archived (and disabled) so existing
/// projects do not silently keep using a deprecated alias.
class DeepSeekV4ModelsMigration extends Migration {
  final ILoggingService _logger;

  DeepSeekV4ModelsMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'deepseek_v4_models';

  @override
  String get description => 'Upgrade DeepSeek provider to v4 models';

  @override
  int get priority => 160;

  @override
  Future<bool> isApplied() async {
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM llm_provider_models WHERE model_id = 'deepseek-v4-flash'",
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    try {
      // Bump the provider context window and switch the default model to v4-flash.
      await DatabaseService.execute('''
        UPDATE translation_providers
        SET default_model = 'deepseek-v4-flash',
            max_context_tokens = 1000000
        WHERE code = 'deepseek'
      ''');

      // Insert the new v4 models. is_default = 0 because the global default
      // selection is owned by the provider table / user preferences.
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_deepseek_v4_flash', 'deepseek', 'deepseek-v4-flash', 'DeepSeek V4 Flash', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_deepseek_v4_pro', 'deepseek', 'deepseek-v4-pro', 'DeepSeek V4 Pro', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      // Archive the legacy deepseek-chat row (DeepSeek deprecates it on 2026/07/24).
      await DatabaseService.execute('''
        UPDATE llm_provider_models
        SET is_enabled = 0,
            is_archived = 1,
            updated_at = strftime('%s', 'now')
        WHERE provider_code = 'deepseek' AND model_id = 'deepseek-chat'
      ''');

      _logger.info('DeepSeek v4 models added and legacy deepseek-chat archived');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to upgrade DeepSeek to v4 models', e, stackTrace);
      return false;
    }
  }
}
