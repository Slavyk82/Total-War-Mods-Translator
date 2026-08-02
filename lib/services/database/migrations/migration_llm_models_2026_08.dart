import '../../service_locator.dart';
import '../../shared/i_logging_service.dart';
import '../database_service.dart';
import 'migration_base.dart';

/// Migration adding the August 2026 model refresh across the three LLM
/// providers, and retiring the superseded Gemini 3 previews.
///
/// OpenAI (https://developers.openai.com/api/docs/models):
///   - gpt-5.6-terra — GPT-5.6 Terra (1.05M context, 128K max output)
///   - gpt-5.4-nano  — GPT-5.4 nano  (400K context, 128K max output)
///
/// Anthropic (https://platform.claude.com/docs/en/home):
///   - claude-sonnet-5 — Claude Sonnet 5
///   - claude-opus-5   — Claude Opus 5
///
/// Google Gemini (https://ai.google.dev/gemini-api/docs/models):
///   - gemini-3.6-flash      — Gemini 3.6 Flash
///   - gemini-3.5-flash      — Gemini 3.5 Flash
///   - gemini-3.5-flash-lite — Gemini 3.5 Flash-Lite
///
/// The two Gemini 3 previews (`gemini-3-pro-preview`, `gemini-3-flash-preview`)
/// are archived — the same retirement path used for gpt-5.1 and Sonnet 4.5 —
/// so the model picker stops offering them while historical rows survive.
/// Because `gemini-3-flash-preview` was also the Gemini provider default,
/// `translation_providers.default_model` is repointed to `gemini-3.6-flash`.
///
/// Existing provider defaults for OpenAI (gpt-5.5) and Anthropic
/// (claude-sonnet-4-6) are deliberately left untouched: this migration only
/// widens the choice offered in the picker.
class LlmModels202608Migration extends Migration {
  final ILoggingService _logger;

  LlmModels202608Migration({ILoggingService? logger})
      : _logger = logger ?? ServiceLocator.get<ILoggingService>();

  /// The Gemini 3 previews replaced by the 3.5 / 3.6 family.
  static const String _retiredGeminiModels =
      "'gemini-3-pro-preview', 'gemini-3-flash-preview'";

  @override
  String get id => 'llm_models_2026_08';

  @override
  String get description =>
      'Add GPT-5.6 Terra / 5.4 nano, Claude Sonnet 5 / Opus 5 and the '
      'Gemini 3.5 / 3.6 models; archive the Gemini 3 previews';

  @override
  int get priority => 260;

  @override
  Future<bool> isApplied() async {
    final result = await DatabaseService.database.rawQuery(
      "SELECT COUNT(*) as cnt FROM llm_provider_models "
      "WHERE model_id = 'gemini-3.6-flash'",
    );
    return (result.first['cnt'] as int) > 0;
  }

  @override
  Future<bool> execute() async {
    try {
      // Was one of the retired previews still the model-level default?
      // Captured before the archive step below clears the flag; decides
      // whether Gemini 3.6 Flash inherits it. If the user starred another
      // model, this is false and their choice must be preserved.
      final legacyDefault = await DatabaseService.database.rawQuery(
        "SELECT COUNT(*) as cnt FROM llm_provider_models "
        "WHERE provider_code = 'gemini' "
        "AND model_id IN ($_retiredGeminiModels) AND is_default = 1",
      );
      final legacyWasDefault = ((legacyDefault.first['cnt'] as int?) ?? 0) > 0;

      // Insert the new aliases with is_default = 0: the single-default trigger
      // (trg_llm_models_single_default) is BEFORE UPDATE only and does NOT
      // fire on INSERT, so inserting with is_default = 1 would silently create
      // a second default next to a user-chosen one.
      await DatabaseService.execute('''
        INSERT OR IGNORE INTO llm_provider_models
        (id, provider_code, model_id, display_name, is_enabled, is_default, is_archived, created_at, updated_at, last_fetched_at)
        VALUES
        ('model_gpt_5_6_terra', 'openai', 'gpt-5.6-terra', 'GPT-5.6 Terra', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
        ('model_gpt_5_4_nano', 'openai', 'gpt-5.4-nano', 'GPT-5.4 nano', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
        ('model_claude_sonnet_5', 'anthropic', 'claude-sonnet-5', 'Claude Sonnet 5', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
        ('model_claude_opus_5', 'anthropic', 'claude-opus-5', 'Claude Opus 5', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
        ('model_gemini_3_6_flash', 'gemini', 'gemini-3.6-flash', 'Gemini 3.6 Flash', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
        ('model_gemini_3_5_flash', 'gemini', 'gemini-3.5-flash', 'Gemini 3.5 Flash', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now')),
        ('model_gemini_3_5_flash_lite', 'gemini', 'gemini-3.5-flash-lite', 'Gemini 3.5 Flash-Lite', 1, 0, 0, strftime('%s', 'now'), strftime('%s', 'now'), strftime('%s', 'now'))
      ''');

      // Archive the Gemini 3 previews. is_default is cleared in the same
      // statement so the new default sticks (and so the BEFORE UPDATE guard
      // trg_llm_models_prevent_default_archived never sees is_default = 1
      // alongside is_archived = 1).
      await DatabaseService.execute('''
        UPDATE llm_provider_models
        SET is_enabled = 0,
            is_archived = 1,
            is_default = 0,
            updated_at = strftime('%s', 'now')
        WHERE provider_code = 'gemini' AND model_id IN ($_retiredGeminiModels)
      ''');

      // Repoint the provider default only when it still names a retired
      // preview, so a value set by a later migration is never clobbered.
      await DatabaseService.execute('''
        UPDATE translation_providers
        SET default_model = 'gemini-3.6-flash'
        WHERE code = 'gemini' AND default_model IN ($_retiredGeminiModels)
      ''');

      // Only when the cleared legacy row WAS the default does Gemini 3.6 Flash
      // inherit it — and via UPDATE, so the single-default trigger clears any
      // other default for the provider.
      if (legacyWasDefault) {
        await DatabaseService.execute('''
          UPDATE llm_provider_models
          SET is_default = 1,
              updated_at = strftime('%s', 'now')
          WHERE provider_code = 'gemini' AND model_id = 'gemini-3.6-flash'
        ''');
      }

      _logger.info(
          'August 2026 models added (GPT-5.6 Terra / 5.4 nano, Claude Sonnet 5 '
          '/ Opus 5, Gemini 3.5 / 3.6); Gemini 3 previews archived');
      return true;
    } catch (e, stackTrace) {
      _logger.error('Failed to add the August 2026 LLM models', e, stackTrace);
      return false;
    }
  }
}
