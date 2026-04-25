import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration to upgrade the Anthropic provider to the Claude 4.7 / 4.6 family.
///
/// API Documentation: https://platform.claude.com/docs/en/home
/// Adds the new aliases:
///   - claude-opus-4-7   — Opus 4.7
///   - claude-sonnet-4-6 — Sonnet 4.6 (new provider default)
/// Both are exposed by alias only (no dated snapshot in the docs).
///
/// Haiku 4.5 (`claude-haiku-4-5-20251001`) is already seeded by schema.sql
/// and stays untouched. The previous Sonnet 4.5 snapshot is archived so the
/// model picker stops surfacing a superseded version.
class AnthropicOpus47Sonnet46Migration extends Migration {
  final ILoggingService _logger;

  AnthropicOpus47Sonnet46Migration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  @override
  String get id => 'anthropic_opus47_sonnet46';

  @override
  String get description =>
      'Upgrade Anthropic provider to Claude Opus 4.7 / Sonnet 4.6';

  @override
  int get priority => 180;

  @override
  Future<bool> isApplied() async {
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM llm_provider_models WHERE model_id = 'claude-sonnet-4-6'",
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    try {
      // Promote Sonnet 4.6 as the Anthropic provider default.
      await DatabaseService.execute('''
        UPDATE translation_providers
        SET default_model = 'claude-sonnet-4-6'
        WHERE code = 'anthropic'
      ''');

      // Insert the new aliases. is_default = 1 on Sonnet 4.6 so the model
      // picker has a clear primary choice; is_default = 0 on Opus 4.7.
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_claude_sonnet_4_6', 'anthropic', 'claude-sonnet-4-6', 'Claude Sonnet 4.6', 1, 1, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_claude_opus_4_7', 'anthropic', 'claude-opus-4-7', 'Claude Opus 4.7', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      // Archive the superseded Sonnet 4.5 snapshot. Clear is_default too so
      // the new Sonnet 4.6 default sticks.
      await DatabaseService.execute('''
        UPDATE llm_provider_models
        SET is_enabled = 0,
            is_archived = 1,
            is_default = 0,
            updated_at = strftime('%s', 'now')
        WHERE provider_code = 'anthropic' AND model_id = 'claude-sonnet-4-5-20250929'
      ''');

      _logger.info('Anthropic Opus 4.7 / Sonnet 4.6 added; Sonnet 4.5 archived');
      return true;
    } catch (e, stackTrace) {
      _logger.error(
          'Failed to upgrade Anthropic to Opus 4.7 / Sonnet 4.6', e, stackTrace);
      return false;
    }
  }
}
