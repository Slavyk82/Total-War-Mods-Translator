import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to upgrade the OpenAI provider to the GPT-5.4 / 5.5 family.
///
/// API Documentation: https://developers.openai.com/api/docs/models
/// Replaces the previous default (`gpt-5.1-2025-11-13`) with:
///   - gpt-5.5 (new default) — 1M context, 128K max output
///   - gpt-5.4               — 1M context, 128K max output, cheaper
/// Both models are exposed by alias only (no dated snapshot in the docs).
///
/// The legacy gpt-5.1 row is archived (and disabled) so existing projects
/// stop pinning a superseded snapshot.
class OpenAiGpt5xModelsMigration extends Migration {
  final ILoggingService _logger;

  OpenAiGpt5xModelsMigration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'openai_v5_4_5_5_models';

  @override
  String get description => 'Upgrade OpenAI provider to GPT-5.4 / 5.5 models';

  @override
  int get priority => 170;

  @override
  Future<bool> isApplied() async {
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM llm_provider_models WHERE model_id = 'gpt-5.5'",
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    try {
      // Promote gpt-5.5 as the OpenAI provider default and bump the context
      // window to 1M tokens (the v5.4/5.5 family share that limit).
      await DatabaseService.execute('''
        UPDATE translation_providers
        SET default_model = 'gpt-5.5',
            max_context_tokens = 1000000
        WHERE code = 'openai'
      ''');

      // Insert the new aliases. is_default = 0 because the global default
      // selection is owned by the provider table / user preferences.
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_gpt_5_5', 'openai', 'gpt-5.5', 'GPT-5.5', 1, 1, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_gpt_5_4', 'openai', 'gpt-5.4', 'GPT-5.4', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      // Archive the previous default snapshot. If gpt-5.1 was flagged as the
      // provider-level default, clear that flag too so the new default sticks.
      await DatabaseService.execute('''
        UPDATE llm_provider_models
        SET is_enabled = 0,
            is_archived = 1,
            is_default = 0,
            updated_at = strftime('%s', 'now')
        WHERE provider_code = 'openai' AND model_id = 'gpt-5.1-2025-11-13'
      ''');

      _logger.info('OpenAI v5.4/5.5 models added; legacy gpt-5.1 archived');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to upgrade OpenAI to v5.4/5.5 models', e, stackTrace);
      return false;
    }
  }
}
