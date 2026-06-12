/// Settings keys constants
class SettingsKeys {
  // General
  static const String workshopPath = 'workshop_path';
  static const String rpfmPath = 'rpfm_path';
  static const String rpfmSchemaPath = 'rpfm_schema_path';
  static const String defaultTargetLanguage = 'default_target_language';

  // Pack generation
  static const String packPrefix = 'pack_prefix';

  // Default values
  static const String defaultTargetLanguageValue = 'fr';
  static const String autoUpdate = 'auto_update';

  // Game installation paths (per game)
  static const String gamePathWh3 = 'game_path_wh3';
  static const String gamePathWh2 = 'game_path_wh2';
  static const String gamePathWh = 'game_path_wh';
  static const String gamePathRome2 = 'game_path_rome2';
  static const String gamePathAttila = 'game_path_attila';
  static const String gamePathTroy = 'game_path_troy';
  static const String gamePath3k = 'game_path_3k';
  static const String gamePathPharaoh = 'game_path_pharaoh';
  static const String gamePathPharaohDynasties = 'game_path_pharaoh_dynasties';

  // LLM Providers
  static const String activeProvider = 'active_llm_provider';
  static const String anthropicApiKey = 'anthropic_api_key';
  static const String anthropicModel = 'anthropic_model';
  static const String openaiApiKey = 'openai_api_key';
  static const String openaiModel = 'openai_model';
  static const String deeplApiKey = 'deepl_api_key';
  static const String deeplPlan = 'deepl_plan';
  static const String deepseekApiKey = 'deepseek_api_key';
  static const String deepseekModel = 'deepseek_model';
  static const String geminiApiKey = 'gemini_api_key';
  static const String geminiModel = 'gemini_model';
  static const String rateLimit = 'rate_limit';

  // Steam credentials
  static const String steamUsername = 'steam_username';
  static const String steamPassword = 'steam_password';

  // Workshop publish templates
  static const String workshopTitleTemplate = 'workshop_title_template';
  static const String workshopDescriptionTemplate = 'workshop_description_template';
  static const String workshopDefaultVisibility = 'workshop_default_visibility';

  // Workshop onboarding
  static const String workshopOnboardingCardHidden =
      'workshop_onboarding_card_hidden';

  // Translation editor preferences
  static const String editorSelectedLlmModelId =
      'editor_selected_llm_model_id';
}
