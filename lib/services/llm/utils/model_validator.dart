/// Validates LLM model identifiers against their providers.
///
/// Ensures that model IDs are compatible with their declared provider,
/// preventing configuration mismatches like "gpt-4" with "anthropic" provider.
///
/// Uses a blocklist approach: only rejects obvious cross-provider mismatches
/// rather than trying to enumerate all valid models (which is impractical
/// given OpenAI's ever-changing model naming).
class LlmModelValidator {
  LlmModelValidator._();

  /// Model prefixes that are exclusive to a specific provider.
  /// If a model starts with one of these, it MUST be from that provider.
  static const Map<String, String> _exclusivePrefixes = {
    'claude': 'anthropic',
    'gpt': 'openai',
    'deepl': 'deepl',
  };

  /// Validates that a model ID is compatible with the given provider.
  ///
  /// Uses blocklist approach: rejects models that clearly belong to another provider.
  /// Returns null if valid, or an error message if invalid.
  static String? validate(String providerCode, String modelId) {
    if (providerCode.isEmpty) {
      return 'Provider code cannot be empty';
    }

    if (modelId.isEmpty) {
      return 'Model ID cannot be empty';
    }

    final normalizedProvider = providerCode.toLowerCase().trim();
    final normalizedModel = modelId.toLowerCase().trim();

    // Check if model has an exclusive prefix belonging to a different provider
    for (final entry in _exclusivePrefixes.entries) {
      final prefix = entry.key;
      final expectedProvider = entry.value;

      if (normalizedModel.startsWith(prefix) &&
          normalizedProvider != expectedProvider) {
        return 'Model "$modelId" belongs to provider "$expectedProvider", '
            'not "$providerCode"';
      }
    }

    return null;
  }

  /// Validates and throws if invalid.
  ///
  /// Throws [ArgumentError] if validation fails.
  static void validateOrThrow(String providerCode, String modelId) {
    final error = validate(providerCode, modelId);
    if (error != null) {
      throw ArgumentError(error);
    }
  }

  /// Returns true if the model is valid for the provider.
  static bool isValid(String providerCode, String modelId) {
    return validate(providerCode, modelId) == null;
  }

  /// Infers the provider code from a model ID.
  ///
  /// Returns null if the provider cannot be determined.
  static String? inferProvider(String modelId) {
    final normalizedModel = modelId.toLowerCase().trim();

    for (final entry in _exclusivePrefixes.entries) {
      final prefix = entry.key;
      final provider = entry.value;

      if (normalizedModel.startsWith(prefix)) {
        return provider;
      }
    }

    return null;
  }

  /// Returns a list of known providers.
  static List<String> get knownProviders =>
      _exclusivePrefixes.values.toSet().toList();
}

