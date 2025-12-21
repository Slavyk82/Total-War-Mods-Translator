import 'package:json_annotation/json_annotation.dart';

part 'llm_provider_config.g.dart';

/// Configuration for an LLM provider
/// 
/// Note: Available models are loaded dynamically from the database
/// via LlmModelManagementService. This class only contains static
/// provider configuration (endpoints, rate limits, etc.).
@JsonSerializable()
class LlmProviderConfig {
  /// Provider code (e.g., "anthropic", "openai", "deepl")
  final String providerCode;

  /// Provider display name
  final String providerName;

  /// API base URL
  final String apiBaseUrl;

  /// Supports streaming responses
  final bool supportsStreaming;

  /// Token limit per request (input + output)
  final int maxTokensPerRequest;

  /// Default rate limit (requests per minute)
  final int defaultRateLimitRpm;

  /// Default rate limit (tokens per minute), null if not applicable
  final int? defaultRateLimitTpm;

  /// Retry configuration
  final RetryConfig retryConfig;

  const LlmProviderConfig({
    required this.providerCode,
    required this.providerName,
    required this.apiBaseUrl,
    required this.supportsStreaming,
    required this.maxTokensPerRequest,
    required this.defaultRateLimitRpm,
    this.defaultRateLimitTpm,
    required this.retryConfig,
  });

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) =>
      _$LlmProviderConfigFromJson(json);

  Map<String, dynamic> toJson() => _$LlmProviderConfigToJson(this);

  /// Anthropic (Claude) configuration
  static LlmProviderConfig get anthropic => LlmProviderConfig(
        providerCode: 'anthropic',
        providerName: 'Anthropic (Claude)',
        apiBaseUrl: 'https://api.anthropic.com/v1',
        supportsStreaming: true,
        maxTokensPerRequest: 200000,
        defaultRateLimitRpm: 50,
        defaultRateLimitTpm: 40000,
        retryConfig: RetryConfig.defaultConfig,
      );

  /// OpenAI configuration
  static LlmProviderConfig get openai => LlmProviderConfig(
        providerCode: 'openai',
        providerName: 'OpenAI',
        apiBaseUrl: 'https://api.openai.com/v1',
        supportsStreaming: true,
        maxTokensPerRequest: 128000,
        defaultRateLimitRpm: 500,
        defaultRateLimitTpm: 150000,
        retryConfig: RetryConfig.defaultConfig,
      );

  /// DeepL configuration
  static LlmProviderConfig get deepl => LlmProviderConfig(
        providerCode: 'deepl',
        providerName: 'DeepL',
        apiBaseUrl: 'https://api.deepl.com/v2',
        supportsStreaming: false,
        maxTokensPerRequest: 100000, // Characters, not tokens
        defaultRateLimitRpm: 100,
        defaultRateLimitTpm: null, // Character-based billing
        retryConfig: RetryConfig.defaultConfig,
      );

  /// DeepSeek configuration
  /// API Documentation: https://api-docs.deepseek.com/
  /// Uses OpenAI-compatible API format
  static LlmProviderConfig get deepseek => LlmProviderConfig(
        providerCode: 'deepseek',
        providerName: 'DeepSeek',
        apiBaseUrl: 'https://api.deepseek.com',
        supportsStreaming: true,
        maxTokensPerRequest: 64000, // Context window for deepseek-chat
        defaultRateLimitRpm: 60,
        defaultRateLimitTpm: 100000,
        retryConfig: RetryConfig.defaultConfig,
      );

  /// Google Gemini configuration
  /// API Documentation: https://ai.google.dev/gemini-api/docs
  /// Models: gemini-3-pro-preview, gemini-3-flash-preview
  static LlmProviderConfig get gemini => LlmProviderConfig(
        providerCode: 'gemini',
        providerName: 'Google Gemini',
        apiBaseUrl: 'https://generativelanguage.googleapis.com/v1beta',
        supportsStreaming: true,
        maxTokensPerRequest: 1048576, // 1M context window
        defaultRateLimitRpm: 60,
        defaultRateLimitTpm: 250000,
        retryConfig: RetryConfig.defaultConfig,
      );

  LlmProviderConfig copyWith({
    String? providerCode,
    String? providerName,
    String? apiBaseUrl,
    bool? supportsStreaming,
    int? maxTokensPerRequest,
    int? defaultRateLimitRpm,
    int? defaultRateLimitTpm,
    RetryConfig? retryConfig,
  }) {
    return LlmProviderConfig(
      providerCode: providerCode ?? this.providerCode,
      providerName: providerName ?? this.providerName,
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      supportsStreaming: supportsStreaming ?? this.supportsStreaming,
      maxTokensPerRequest: maxTokensPerRequest ?? this.maxTokensPerRequest,
      defaultRateLimitRpm: defaultRateLimitRpm ?? this.defaultRateLimitRpm,
      defaultRateLimitTpm: defaultRateLimitTpm ?? this.defaultRateLimitTpm,
      retryConfig: retryConfig ?? this.retryConfig,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmProviderConfig &&
          runtimeType == other.runtimeType &&
          providerCode == other.providerCode &&
          providerName == other.providerName &&
          apiBaseUrl == other.apiBaseUrl &&
          supportsStreaming == other.supportsStreaming &&
          maxTokensPerRequest == other.maxTokensPerRequest &&
          defaultRateLimitRpm == other.defaultRateLimitRpm &&
          defaultRateLimitTpm == other.defaultRateLimitTpm &&
          retryConfig == other.retryConfig;

  @override
  int get hashCode =>
      providerCode.hashCode ^
      providerName.hashCode ^
      apiBaseUrl.hashCode ^
      supportsStreaming.hashCode ^
      maxTokensPerRequest.hashCode ^
      defaultRateLimitRpm.hashCode ^
      (defaultRateLimitTpm?.hashCode ?? 0) ^
      retryConfig.hashCode;

  @override
  String toString() {
    return 'LlmProviderConfig($providerName, '
        'maxTokens: $maxTokensPerRequest, rpm: $defaultRateLimitRpm)';
  }
}

/// Retry configuration for LLM requests
@JsonSerializable()
class RetryConfig {
  /// Maximum number of retries
  final int maxRetries;

  /// Initial delay in milliseconds
  final int initialDelayMs;

  /// Maximum delay in milliseconds
  final int maxDelayMs;

  /// Backoff multiplier (exponential backoff)
  final double backoffMultiplier;

  /// Retry on rate limit errors
  final bool retryOnRateLimit;

  /// Retry on timeout errors
  final bool retryOnTimeout;

  /// Retry on server errors (5xx)
  final bool retryOnServerError;

  const RetryConfig({
    required this.maxRetries,
    required this.initialDelayMs,
    required this.maxDelayMs,
    required this.backoffMultiplier,
    required this.retryOnRateLimit,
    required this.retryOnTimeout,
    required this.retryOnServerError,
  });

  factory RetryConfig.fromJson(Map<String, dynamic> json) =>
      _$RetryConfigFromJson(json);

  Map<String, dynamic> toJson() => _$RetryConfigToJson(this);

  /// Default retry configuration
  static const RetryConfig defaultConfig = RetryConfig(
    maxRetries: 3,
    initialDelayMs: 1000,
    maxDelayMs: 30000,
    backoffMultiplier: 2.0,
    retryOnRateLimit: true,
    retryOnTimeout: true,
    retryOnServerError: true,
  );

  /// Calculate delay for a given retry attempt
  int calculateDelay(int attemptNumber) {
    if (attemptNumber <= 0) return 0;
    final delay =
        (initialDelayMs * Math.pow(backoffMultiplier, attemptNumber - 1))
            .toInt();
    return delay > maxDelayMs ? maxDelayMs : delay;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetryConfig &&
          runtimeType == other.runtimeType &&
          maxRetries == other.maxRetries &&
          initialDelayMs == other.initialDelayMs &&
          maxDelayMs == other.maxDelayMs &&
          backoffMultiplier == other.backoffMultiplier &&
          retryOnRateLimit == other.retryOnRateLimit &&
          retryOnTimeout == other.retryOnTimeout &&
          retryOnServerError == other.retryOnServerError;

  @override
  int get hashCode =>
      maxRetries.hashCode ^
      initialDelayMs.hashCode ^
      maxDelayMs.hashCode ^
      backoffMultiplier.hashCode ^
      retryOnRateLimit.hashCode ^
      retryOnTimeout.hashCode ^
      retryOnServerError.hashCode;

  @override
  String toString() {
    return 'RetryConfig(maxRetries: $maxRetries, initialDelay: ${initialDelayMs}ms, '
        'maxDelay: ${maxDelayMs}ms, backoff: $backoffMultiplier)';
  }
}

// Helper for math operations
class Math {
  static double pow(double base, int exponent) {
    if (exponent == 0) return 1.0;
    double result = base;
    for (int i = 1; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
