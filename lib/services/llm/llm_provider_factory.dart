import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/providers/anthropic_provider.dart';
import 'package:twmt/services/llm/providers/openai_provider.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';

/// Factory for creating LLM provider instances
class LlmProviderFactory {
  /// Singleton instance
  static final LlmProviderFactory _instance = LlmProviderFactory._internal();

  /// Provider instances cache
  final Map<String, ILlmProvider> _providers = {};

  factory LlmProviderFactory() => _instance;

  LlmProviderFactory._internal() {
    // Pre-initialize all providers
    _providers['anthropic'] = AnthropicProvider();
    _providers['openai'] = OpenAiProvider();
    _providers['deepl'] = DeepLProvider();
  }

  /// Get provider by code
  ///
  /// [providerCode] - Provider code ('anthropic', 'openai', 'deepl')
  ///
  /// Returns provider instance or throws if not found
  ILlmProvider getProvider(String providerCode) {
    final provider = _providers[providerCode.toLowerCase()];
    if (provider == null) {
      throw LlmConfigurationException(
        'Unknown provider: $providerCode',
        code: 'UNKNOWN_PROVIDER',
        details: {
          'providerCode': providerCode,
          'availableProviders': _providers.keys.toList(),
        },
      );
    }
    return provider;
  }

  /// Get all available provider codes
  List<String> getAvailableProviders() {
    return _providers.keys.toList();
  }

  /// Check if provider exists
  bool hasProvider(String providerCode) {
    return _providers.containsKey(providerCode.toLowerCase());
  }

  /// Get all providers
  Map<String, ILlmProvider> getAllProviders() {
    return Map.unmodifiable(_providers);
  }

  /// Register a custom provider
  ///
  /// Useful for testing or adding custom LLM providers
  void registerProvider(String providerCode, ILlmProvider provider) {
    _providers[providerCode.toLowerCase()] = provider;
  }

  /// Unregister a provider
  void unregisterProvider(String providerCode) {
    _providers.remove(providerCode.toLowerCase());
  }

  /// Clear all providers (useful for testing)
  void clearProviders() {
    _providers.clear();
  }

  /// Reset to default providers
  void resetToDefaults() {
    _providers.clear();
    _providers['anthropic'] = AnthropicProvider();
    _providers['openai'] = OpenAiProvider();
    _providers['deepl'] = DeepLProvider();
  }
}
