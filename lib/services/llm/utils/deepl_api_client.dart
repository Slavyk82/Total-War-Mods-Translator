import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';

/// Low-level API client for DeepL translation service.
///
/// Handles:
/// - HTTP client setup and configuration
/// - FREE vs PRO endpoint detection
/// - Error handling and exception mapping
/// - Common API operations (translate, usage, languages)
///
/// This client is used by [DeepLProvider] for translation operations
/// and can be extended for glossary operations.
class DeepLApiClient {
  final Dio _dio;
  static const String _providerCode = 'deepl';

  /// DeepL API base URL for PRO accounts
  static const String apiBaseUrlPro = 'https://api.deepl.com/v2';

  /// DeepL API base URL for FREE accounts (keys ending with ':fx')
  static const String apiBaseUrlFree = 'https://api-free.deepl.com/v2';

  DeepLApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: LlmProviderConfig.deepl.apiBaseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Content-Type': 'application/json',
              },
            ));

  /// Get the Dio instance for advanced operations.
  Dio get dio => _dio;

  /// Determine the correct API base URL based on the API key type.
  ///
  /// FREE API keys end with ':fx'.
  static String getBaseUrl(String? apiKey) {
    if (apiKey != null && apiKey.endsWith(':fx')) {
      return apiBaseUrlFree;
    }
    return LlmProviderConfig.deepl.apiBaseUrl;
  }

  /// Update the base URL dynamically based on API key.
  ///
  /// Call this before making API requests to ensure the correct
  /// endpoint (FREE vs PRO) is used.
  void updateBaseUrl(String apiKey) {
    _dio.options.baseUrl = getBaseUrl(apiKey);
  }

  /// Create authorization headers for DeepL API.
  Map<String, String> createAuthHeaders(String apiKey) {
    return {
      'Authorization': 'DeepL-Auth-Key $apiKey',
    };
  }

  /// Make a translate request to DeepL API.
  ///
  /// [texts] - List of texts to translate
  /// [targetLang] - Target language in DeepL format
  /// [sourceLang] - Optional source language in DeepL format
  /// [glossaryId] - Optional DeepL glossary ID
  /// [apiKey] - DeepL API key
  /// [cancelToken] - Optional cancellation token
  Future<Response<dynamic>> translate({
    required List<String> texts,
    required String targetLang,
    String? sourceLang,
    String? glossaryId,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    updateBaseUrl(apiKey);

    final payload = <String, dynamic>{
      'text': texts,
      'target_lang': targetLang,
      'formality': 'default',
      'preserve_formatting': true,
      'tag_handling': 'xml',
      'split_sentences': 'nonewlines',
    };

    if (sourceLang != null) {
      payload['source_lang'] = sourceLang;
    }

    if (glossaryId != null) {
      payload['glossary_id'] = glossaryId;
    }

    return _dio.post(
      '/translate',
      data: payload,
      cancelToken: cancelToken,
      options: Options(headers: createAuthHeaders(apiKey)),
    );
  }

  /// Get usage information (character count and limit).
  Future<Response<dynamic>> getUsage(String apiKey) async {
    updateBaseUrl(apiKey);
    return _dio.get(
      '/usage',
      options: Options(headers: createAuthHeaders(apiKey)),
    );
  }

  /// Get supported languages from DeepL.
  ///
  /// [type] - 'source' or 'target'
  Future<Response<dynamic>> getLanguages({
    required String apiKey,
    required String type,
  }) async {
    updateBaseUrl(apiKey);
    return _dio.get(
      '/languages',
      queryParameters: {'type': type},
      options: Options(headers: createAuthHeaders(apiKey)),
    );
  }

  /// Check if service is available.
  Future<Response<dynamic>> checkAvailability() async {
    return _dio.get(
      '/usage',
      options: Options(
        validateStatus: (status) => status != null,
      ),
    );
  }

  // ===========================================================================
  // Glossary API Operations
  // ===========================================================================

  /// Create a glossary on DeepL.
  Future<Response<dynamic>> createGlossary({
    required String name,
    required String targetLang,
    required String entries,
    required String apiKey,
  }) async {
    updateBaseUrl(apiKey);

    final payload = {
      'name': name,
      'target_lang': targetLang,
      'entries': entries,
      'entries_format': 'tsv',
    };

    return _dio.post(
      '/glossaries',
      data: payload,
      options: Options(headers: createAuthHeaders(apiKey)),
    );
  }

  /// List all glossaries.
  Future<Response<dynamic>> listGlossaries(String apiKey) async {
    updateBaseUrl(apiKey);
    return _dio.get(
      '/glossaries',
      options: Options(headers: createAuthHeaders(apiKey)),
    );
  }

  /// Delete a glossary.
  Future<Response<dynamic>> deleteGlossary({
    required String glossaryId,
    required String apiKey,
  }) async {
    updateBaseUrl(apiKey);
    return _dio.delete(
      '/glossaries/$glossaryId',
      options: Options(headers: createAuthHeaders(apiKey)),
    );
  }

  // ===========================================================================
  // Error Handling
  // ===========================================================================

  /// Convert a Dio exception to an appropriate LLM exception.
  ///
  /// Maps DeepL-specific error codes to [LlmProviderException] subtypes.
  LlmProviderException handleDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;

    // Extract error message from DeepL response
    String errorMessage = 'Unknown error';

    if (responseData is Map<String, dynamic>) {
      errorMessage = responseData['message'] as String? ?? errorMessage;
    } else if (responseData is String) {
      errorMessage = responseData;
    }

    // Handle authentication errors
    if (statusCode == 403) {
      return LlmAuthenticationException(
        'Invalid API key or insufficient quota: $errorMessage',
        providerCode: _providerCode,
      );
    }

    // Handle quota exceeded (DeepL-specific status code)
    if (statusCode == 456) {
      return LlmQuotaException(
        'Quota exceeded: $errorMessage',
        providerCode: _providerCode,
      );
    }

    // Handle rate limit errors
    if (statusCode == 429) {
      final retryAfter = e.response?.headers.value('retry-after');
      return LlmRateLimitException(
        'Too many requests: $errorMessage',
        providerCode: _providerCode,
        retryAfterSeconds: retryAfter != null ? int.tryParse(retryAfter) : null,
      );
    }

    // Handle invalid request errors
    if (statusCode == 400) {
      return LlmInvalidRequestException(
        'Invalid request: $errorMessage',
        providerCode: _providerCode,
      );
    }

    // Handle unsupported language errors
    if (statusCode == 404) {
      return LlmInvalidRequestException(
        'Unsupported language pair: $errorMessage',
        providerCode: _providerCode,
      );
    }

    // Handle other 4xx errors
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return LlmInvalidRequestException(
        errorMessage,
        providerCode: _providerCode,
      );
    }

    // Handle server errors
    if (statusCode != null && statusCode >= 500) {
      return LlmServerException(
        'Server error: $errorMessage',
        providerCode: _providerCode,
        statusCode: statusCode,
      );
    }

    // Handle timeout errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return LlmNetworkException(
        'Request timeout: ${e.message}',
        providerCode: _providerCode,
      );
    }

    // Handle connection errors
    if (e.type == DioExceptionType.connectionError) {
      return LlmNetworkException(
        'Connection failed: ${e.message}',
        providerCode: _providerCode,
      );
    }

    // Default network error
    return LlmNetworkException(
      'Network error: ${e.message ?? errorMessage}',
      providerCode: _providerCode,
    );
  }

  /// Wrap an async operation with Dio exception handling.
  ///
  /// Returns [Ok] with the result or [Err] with a properly mapped exception.
  Future<Result<T, LlmProviderException>> wrapRequest<T>(
    Future<T> Function() operation,
  ) async {
    try {
      final result = await operation();
      return Ok(result);
    } on DioException catch (e) {
      return Err(handleDioException(e));
    } on LlmProviderException catch (e) {
      return Err(e);
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Unexpected error: $e',
        providerCode: _providerCode,
        code: 'UNEXPECTED_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }
}
