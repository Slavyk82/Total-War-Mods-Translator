import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add DeepSeek as a translation provider.
///
/// DeepSeek is an AI model provider with OpenAI-compatible API.
/// Model: deepseek-chat (DeepSeek-V3.2)
/// Max output: Default 4K, Maximum 8K tokens
class DeepSeekProviderMigration extends Migration {
  @override
  String get id => 'deepseek_provider';

  @override
  String get description => 'Add DeepSeek as a translation provider';

  @override
  int get priority => 75;

  @override
  Future<bool> isApplied() async {
    // Check if deepseek provider already exists
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM translation_providers WHERE code = 'deepseek'"
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      // Add DeepSeek to translation_providers
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO translation_providers
        (id, code, name, api_endpoint, default_model, max_context_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at)
        VALUES
        ('provider_deepseek', 'deepseek', 'DeepSeek', 'https://api.deepseek.com', 'deepseek-chat', 64000, 30, 60, 100000, 1, strftime('%s', 'now'))
      ''');

      // Add DeepSeek model to llm_provider_models
      // Note: is_default = 0 to not override existing default provider
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_deepseek_chat', 'deepseek', 'deepseek-chat', 'DeepSeek V3.2', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      logging.info('DeepSeek provider and model added successfully');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add DeepSeek provider', e, stackTrace);
      // Non-fatal: DeepSeek won't be available but other providers still work
      return false;
    }
  }
}
