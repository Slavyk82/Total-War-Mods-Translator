import '../database_service.dart';
import '../../shared/logging_service.dart';
import 'migration_base.dart';

/// Migration to add Google Gemini as a translation provider.
///
/// Google Gemini is an AI model provider.
/// Models: gemini-3-pro-preview, gemini-3-flash-preview
/// Max output: 65,536 tokens
class GeminiProviderMigration extends Migration {
  @override
  String get id => 'gemini_provider';

  @override
  String get description => 'Add Google Gemini as a translation provider';

  @override
  int get priority => 76;

  @override
  Future<bool> isApplied() async {
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM translation_providers WHERE code = 'gemini'"
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    final logging = LoggingService.instance;

    try {
      // Add Gemini to translation_providers
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO translation_providers
        (id, code, name, api_endpoint, default_model, max_context_tokens, max_batch_size, rate_limit_rpm, rate_limit_tpm, is_active, created_at)
        VALUES
        ('provider_gemini', 'gemini', 'Google Gemini', 'https://generativelanguage.googleapis.com/v1beta', 'gemini-3-flash-preview', 1048576, 30, 60, 250000, 1, strftime('%s', 'now'))
      ''');

      // Add Gemini models to llm_provider_models
      // Note: is_default = 0 to not override existing default provider
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_gemini_3_pro', 'gemini', 'gemini-3-pro-preview', 'Gemini 3 Pro', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_gemini_3_flash', 'gemini', 'gemini-3-flash-preview', 'Gemini 3 Flash', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      logging.info('Gemini provider and models added successfully');
      return true;
    } catch (e, stackTrace) {
      logging.error('Failed to add Gemini provider', e, stackTrace);
      return false;
    }
  }
}
