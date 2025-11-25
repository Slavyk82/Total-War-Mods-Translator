import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../services/settings/settings_service.dart';
import '../../../services/service_locator.dart';
import '../../../services/llm/llm_provider_factory.dart';
import '../../../services/llm/llm_model_management_service.dart';
import '../../../models/domain/llm_provider_model.dart';

part 'settings_providers.g.dart';

/// Secure storage for API keys
const _secureStorage = FlutterSecureStorage(
  wOptions: WindowsOptions(useBackwardCompatibility: false),
);

/// Settings keys constants
class SettingsKeys {
  // General
  static const String workshopPath = 'workshop_path';
  static const String rpfmPath = 'rpfm_path';
  static const String rpfmSchemaPath = 'rpfm_schema_path';
  static const String defaultTargetLanguage = 'default_target_language';
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

  // LLM Providers
  static const String activeProvider = 'active_llm_provider';
  static const String anthropicApiKey = 'anthropic_api_key';
  static const String anthropicModel = 'anthropic_model';
  static const String openaiApiKey = 'openai_api_key';
  static const String openaiModel = 'openai_model';
  static const String deeplApiKey = 'deepl_api_key';
  static const String deeplPlan = 'deepl_plan';
  static const String rateLimit = 'rate_limit';

}

/// Provider for settings service
@riverpod
SettingsService settingsService(Ref ref) {
  return ServiceLocator.get<SettingsService>();
}

/// Provider for LLM model management service
@riverpod
LlmModelManagementService llmModelManagementService(Ref ref) {
  return ServiceLocator.get<LlmModelManagementService>();
}

/// General settings notifier
@riverpod
class GeneralSettings extends _$GeneralSettings {
  @override
  Future<Map<String, String>> build() async {
    final service = ref.read(settingsServiceProvider);

    return {
      SettingsKeys.gamePathWh3: await service.getString(SettingsKeys.gamePathWh3),
      SettingsKeys.gamePathWh2: await service.getString(SettingsKeys.gamePathWh2),
      SettingsKeys.gamePathWh: await service.getString(SettingsKeys.gamePathWh),
      SettingsKeys.gamePathRome2: await service.getString(SettingsKeys.gamePathRome2),
      SettingsKeys.gamePathAttila: await service.getString(SettingsKeys.gamePathAttila),
      SettingsKeys.gamePathTroy: await service.getString(SettingsKeys.gamePathTroy),
      SettingsKeys.gamePath3k: await service.getString(SettingsKeys.gamePath3k),
      SettingsKeys.gamePathPharaoh: await service.getString(SettingsKeys.gamePathPharaoh),
      SettingsKeys.workshopPath: await service.getString(SettingsKeys.workshopPath),
      SettingsKeys.rpfmPath: await service.getString(SettingsKeys.rpfmPath),
      SettingsKeys.rpfmSchemaPath: await service.getString(SettingsKeys.rpfmSchemaPath),
      SettingsKeys.defaultTargetLanguage:
          await service.getString(SettingsKeys.defaultTargetLanguage, defaultValue: 'es'),
      SettingsKeys.autoUpdate:
          (await service.getBool(SettingsKeys.autoUpdate, defaultValue: true)).toString(),
    };
  }

  Future<void> updateGamePath(String gameCode, String path) async {
    final service = ref.read(settingsServiceProvider);
    final key = _getGamePathKey(gameCode);
    await service.setString(key, path);
    ref.invalidateSelf();
  }

  Future<void> updateWorkshopPath(String path) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.workshopPath, path);
    ref.invalidateSelf();
  }

  Future<void> updateRpfmPath(String path) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.rpfmPath, path);
    ref.invalidateSelf();
  }

  Future<void> updateRpfmSchemaPath(String path) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.rpfmSchemaPath, path);
    ref.invalidateSelf();
  }

  String _getGamePathKey(String gameCode) {
    switch (gameCode) {
      case 'wh3':
        return SettingsKeys.gamePathWh3;
      case 'wh2':
        return SettingsKeys.gamePathWh2;
      case 'wh':
        return SettingsKeys.gamePathWh;
      case 'rome2':
        return SettingsKeys.gamePathRome2;
      case 'attila':
        return SettingsKeys.gamePathAttila;
      case 'troy':
        return SettingsKeys.gamePathTroy;
      case '3k':
        return SettingsKeys.gamePath3k;
      case 'pharaoh':
        return SettingsKeys.gamePathPharaoh;
      default:
        throw ArgumentError('Unknown game code: $gameCode');
    }
  }

  Future<void> updateDefaultTargetLanguage(String language) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.defaultTargetLanguage, language);
    ref.invalidateSelf();
  }

  Future<void> updateAutoUpdate(bool enabled) async {
    final service = ref.read(settingsServiceProvider);
    await service.setBool(SettingsKeys.autoUpdate, enabled);
    ref.invalidateSelf();
  }

  Future<void> clearCache() async {
    // Implement cache clearing logic
  }

  Future<void> resetToDefaults() async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.gamePathWh3, '');
    await service.setString(SettingsKeys.gamePathWh2, '');
    await service.setString(SettingsKeys.gamePathWh, '');
    await service.setString(SettingsKeys.gamePathRome2, '');
    await service.setString(SettingsKeys.gamePathAttila, '');
    await service.setString(SettingsKeys.gamePathTroy, '');
    await service.setString(SettingsKeys.gamePath3k, '');
    await service.setString(SettingsKeys.gamePathPharaoh, '');
    await service.setString(SettingsKeys.workshopPath, '');
    await service.setString(SettingsKeys.rpfmPath, '');
    await service.setString(SettingsKeys.rpfmSchemaPath, '');
    await service.setString(SettingsKeys.defaultTargetLanguage, 'es');
    await service.setBool(SettingsKeys.autoUpdate, true);
    ref.invalidateSelf();
  }
}

/// LLM provider settings notifier
@riverpod
class LlmProviderSettings extends _$LlmProviderSettings {
  @override
  Future<Map<String, String>> build() async {
    final service = ref.read(settingsServiceProvider);

    // Load non-sensitive settings from database
    // Models are NOT hardcoded - empty string means "use DB default"
    final provider = await service.getString(
      SettingsKeys.activeProvider,
      defaultValue: 'openai',
    );
    final anthropicModel = await service.getString(
      SettingsKeys.anthropicModel,
      defaultValue: '', // Model loaded from DB if empty
    );
    final openaiModel = await service.getString(
      SettingsKeys.openaiModel,
      defaultValue: '', // Model loaded from DB if empty
    );
    final deeplPlan = await service.getString(
      SettingsKeys.deeplPlan,
      defaultValue: 'free',
    );
    final rateLimit = await service.getInt(
      SettingsKeys.rateLimit,
      defaultValue: 100,
    );

    // Load API keys from secure storage
    final anthropicKey = await _secureStorage.read(key: SettingsKeys.anthropicApiKey) ?? '';
    final openaiKey = await _secureStorage.read(key: SettingsKeys.openaiApiKey) ?? '';
    final deeplKey = await _secureStorage.read(key: SettingsKeys.deeplApiKey) ?? '';

    return {
      SettingsKeys.activeProvider: provider,
      SettingsKeys.anthropicModel: anthropicModel,
      SettingsKeys.anthropicApiKey: anthropicKey,
      SettingsKeys.openaiModel: openaiModel,
      SettingsKeys.openaiApiKey: openaiKey,
      SettingsKeys.deeplPlan: deeplPlan,
      SettingsKeys.deeplApiKey: deeplKey,
      SettingsKeys.rateLimit: rateLimit.toString(),
    };
  }

  Future<void> updateActiveProvider(String provider) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.activeProvider, provider);
    ref.invalidateSelf();
  }

  Future<void> updateAnthropicApiKey(String key) async {
    await _secureStorage.write(key: SettingsKeys.anthropicApiKey, value: key);
    ref.invalidateSelf();
  }

  Future<void> updateAnthropicModel(String model) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.anthropicModel, model);
    ref.invalidateSelf();
  }

  Future<void> updateOpenaiApiKey(String key) async {
    await _secureStorage.write(key: SettingsKeys.openaiApiKey, value: key);
    ref.invalidateSelf();
  }

  Future<void> updateOpenaiModel(String model) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.openaiModel, model);
    ref.invalidateSelf();
  }

  Future<void> updateDeeplApiKey(String key) async {
    await _secureStorage.write(key: SettingsKeys.deeplApiKey, value: key);
    ref.invalidateSelf();
  }

  Future<void> updateDeeplPlan(String plan) async {
    final service = ref.read(settingsServiceProvider);
    await service.setString(SettingsKeys.deeplPlan, plan);
    ref.invalidateSelf();
  }

  Future<void> updateRateLimit(int limit) async {
    final service = ref.read(settingsServiceProvider);
    await service.setInt(SettingsKeys.rateLimit, limit);
    ref.invalidateSelf();
  }

  Future<(bool, String?)> testConnection(String providerCode) async {
    print('[LlmProviderSettings] testConnection called for: $providerCode');

    try {
      // Get API key for the provider
      String? apiKey;
      switch (providerCode) {
        case 'anthropic':
          apiKey = await _secureStorage.read(key: SettingsKeys.anthropicApiKey);
          print('[LlmProviderSettings] Anthropic API key loaded: ${apiKey != null ? "Yes (${apiKey.length} chars)" : "No"}');
          break;
        case 'openai':
          apiKey = await _secureStorage.read(key: SettingsKeys.openaiApiKey);
          print('[LlmProviderSettings] OpenAI API key loaded: ${apiKey != null ? "Yes (${apiKey.length} chars)" : "No"}');
          break;
        case 'deepl':
          apiKey = await _secureStorage.read(key: SettingsKeys.deeplApiKey);
          print('[LlmProviderSettings] DeepL API key loaded: ${apiKey != null ? "Yes (${apiKey.length} chars)" : "No"}');
          break;
        default:
          print('[LlmProviderSettings] Unknown provider: $providerCode');
          return (false, 'Unknown provider');
      }

      // Check if API key exists
      if (apiKey == null || apiKey.isEmpty) {
        print('[LlmProviderSettings] No API key configured for $providerCode');
        return (false, 'No API key configured');
      }

      // Get the first enabled model for this provider (required for validation)
      String? effectiveModel;
      if (providerCode != 'deepl') {
        final modelService = ref.read(llmModelManagementServiceProvider);
        final modelsResult = await modelService.getEnabledModelsByProvider(providerCode);
        if (modelsResult.isOk) {
          final models = modelsResult.unwrap();
          if (models.isNotEmpty) {
            effectiveModel = models.first.modelId;
            print('[LlmProviderSettings] Using first enabled model for validation: $effectiveModel');
          }
        }
        
        if (effectiveModel == null) {
          print('[LlmProviderSettings] No enabled model found for $providerCode');
          return (false, 'No model enabled. Enable at least one model to test the connection.');
        }
      }

      print('[LlmProviderSettings] Getting provider factory...');
      // Get provider instance and test connection
      final providerFactory = ServiceLocator.get<LlmProviderFactory>();
      print('[LlmProviderSettings] Getting provider instance for $providerCode...');
      final provider = providerFactory.getProvider(providerCode);
      print('[LlmProviderSettings] Provider instance obtained: ${provider.providerName}');

      print('[LlmProviderSettings] Calling validateApiKey with model: $effectiveModel...');
      final result = await provider.validateApiKey(apiKey, model: effectiveModel);
      print('[LlmProviderSettings] validateApiKey returned: ${result.isOk ? "OK" : "ERROR"}');

      if (result.isOk) {
        print('[LlmProviderSettings] Connection test SUCCESS for $providerCode');
        return (true, null);
      } else {
        final error = result.unwrapErr();
        print('[LlmProviderSettings] Connection test FAILED for $providerCode: ${error.message}');
        return (false, error.message);
      }
    } catch (e, stackTrace) {
      print('[LlmProviderSettings] Exception in testConnection: $e');
      print('[LlmProviderSettings] Stack trace: $stackTrace');
      return (false, 'Error: $e');
    }
  }

  Future<void> resetToDefaults() async {
    final service = ref.read(settingsServiceProvider);
    
    // Reset provider to default (uses global default model from DB)
    await service.setString(SettingsKeys.activeProvider, 'openai');
    
    // Clear model settings - empty means "use DB default model"
    await service.setString(SettingsKeys.anthropicModel, '');
    await service.setString(SettingsKeys.openaiModel, '');
    
    await service.setString(SettingsKeys.deeplPlan, 'free');
    await service.setInt(SettingsKeys.rateLimit, 100);

    // Clear API keys
    await _secureStorage.delete(key: SettingsKeys.anthropicApiKey);
    await _secureStorage.delete(key: SettingsKeys.openaiApiKey);
    await _secureStorage.delete(key: SettingsKeys.deeplApiKey);

    ref.invalidateSelf();
  }
}

/// Provider for available LLM models for a specific provider
@riverpod
class LlmModels extends _$LlmModels {
  @override
  Future<List<LlmProviderModel>> build(String providerCode) async {
    final service = ref.read(llmModelManagementServiceProvider);
    final result = await service.getAvailableModelsByProvider(providerCode);

    return result.when(
      ok: (models) => models,
      err: (_) => [],
    );
  }

  /// Enable a model
  Future<(bool, String?)> enableModel(String modelId) async {
    print('[LlmModels] Enabling model: $modelId');

    final service = ref.read(llmModelManagementServiceProvider);
    final result = await service.enableModel(modelId);

    if (result.isOk) {
      print('[LlmModels] Successfully enabled model');
      ref.invalidateSelf();
      return (true, null);
    } else {
      final error = result.unwrapErr();
      print('[LlmModels] Failed to enable model: ${error.message}');
      return (false, error.message);
    }
  }

  /// Disable a model
  Future<(bool, String?)> disableModel(String modelId) async {
    print('[LlmModels] Disabling model: $modelId');

    final service = ref.read(llmModelManagementServiceProvider);
    final result = await service.disableModel(modelId);

    if (result.isOk) {
      print('[LlmModels] Successfully disabled model');
      ref.invalidateSelf();
      return (true, null);
    } else {
      final error = result.unwrapErr();
      print('[LlmModels] Failed to disable model: ${error.message}');
      return (false, error.message);
    }
  }

  /// Set a model as the global default.
  ///
  /// Only one model can be default at a time across all providers.
  /// Also updates the global active provider setting to this provider,
  /// so the model becomes the "favorite" for translations.
  /// Note: DeepL is not set as the active LLM provider since it's a
  /// translation API, not an LLM for batch translation.
  Future<(bool, String?)> setAsDefault(String modelId) async {
    print('[LlmModels] Setting model as global default: $modelId');

    final service = ref.read(llmModelManagementServiceProvider);
    final result = await service.setDefaultModel(modelId);

    if (result.isOk) {
      print('[LlmModels] Successfully set model as global default');

      // Also set this provider as the global active provider
      // This makes clicking the star set both the default model AND the favorite provider
      // Skip DeepL - it's a translation API, not an LLM for batch translation
      if (providerCode != 'deepl') {
        print('[LlmModels] Setting $providerCode as active global provider');
        await ref.read(llmProviderSettingsProvider.notifier).updateActiveProvider(providerCode);
      } else {
        print('[LlmModels] Skipping DeepL as active global provider (not an LLM)');
      }

      // Invalidate all provider model lists since default is now global
      _invalidateAllProviderModels();
      // Also invalidate self to refresh current provider's list
      ref.invalidateSelf();
      return (true, null);
    } else {
      final error = result.unwrapErr();
      print('[LlmModels] Failed to set global default model: ${error.message}');
      return (false, error.message);
    }
  }

  /// Invalidate model lists for all known providers.
  ///
  /// Excludes the current provider to avoid self-invalidation error.
  void _invalidateAllProviderModels() {
    const providers = ['anthropic', 'openai', 'deepl'];
    for (final provider in providers) {
      // Skip current provider to avoid self-invalidation error
      if (provider != providerCode) {
        ref.invalidate(llmModelsProvider(provider));
      }
    }
  }

  /// Toggle model enabled status
  Future<(bool, String?)> toggleEnabled(String modelId) async {
    print('[LlmModels] Toggling model enabled status: $modelId');

    final service = ref.read(llmModelManagementServiceProvider);
    final result = await service.toggleModelEnabled(modelId);

    if (result.isOk) {
      print('[LlmModels] Successfully toggled model');
      ref.invalidateSelf();
      return (true, null);
    } else {
      final error = result.unwrapErr();
      print('[LlmModels] Failed to toggle model: ${error.message}');
      return (false, error.message);
    }
  }
}

/// Provider for enabled LLM models for a specific provider
@riverpod
Future<List<LlmProviderModel>> enabledLlmModels(
  Ref ref,
  String providerCode,
) async {
  final service = ref.watch(llmModelManagementServiceProvider);
  final result = await service.getEnabledModelsByProvider(providerCode);

  return result.when(
    ok: (models) => models,
    err: (_) => [],
  );
}

/// Provider for the default LLM model for a specific provider
@riverpod
Future<LlmProviderModel?> defaultLlmModel(
  Ref ref,
  String providerCode,
) async {
  final service = ref.watch(llmModelManagementServiceProvider);
  final result = await service.getDefaultModel(providerCode);

  return result.when(
    ok: (model) => model,
    err: (_) => null,
  );
}
