import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_model_info.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// DeepL provider implementation
///
/// API Documentation: https://developers.deepl.com/docs/api-reference
/// No model selection - single translation engine
/// Character-based pricing (not token-based)
/// Rate Limits: 100 requests/min default
class DeepLProvider implements ILlmProvider {
  final Dio _dio;
  final TokenCalculator _tokenCalculator = TokenCalculator();

  @override
  final String providerCode = 'deepl';

  @override
  final String providerName = 'DeepL';

  @override
  final LlmProviderConfig config = LlmProviderConfig.deepl;

  DeepLProvider({Dio? dio, String? apiKey})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: _getBaseUrl(apiKey),
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Content-Type': 'application/json',
              },
            ));

  /// Determine the correct API base URL based on the API key type
  /// FREE API keys end with ':fx'
  static String _getBaseUrl(String? apiKey) {
    if (apiKey != null && apiKey.endsWith(':fx')) {
      return 'https://api-free.deepl.com/v2';
    }
    return LlmProviderConfig.deepl.apiBaseUrl; // Default to PRO endpoint
  }

  /// Update the base URL dynamically based on API key
  void _updateBaseUrl(String apiKey) {
    _dio.options.baseUrl = _getBaseUrl(apiKey);
  }

  @override
  Future<Result<LlmResponse, LlmProviderException>> translate(
    LlmRequest request,
    String apiKey,
  ) async {
    final startTime = DateTime.now();

    try {
      // Update base URL based on API key type (FREE vs PRO)
      _updateBaseUrl(apiKey);

      // DeepL API supports batch translation - send all texts at once
      final texts = request.texts.values.toList();

      // Build request payload
      final payload = {
        'text': texts,
        'target_lang': _mapLanguageCode(request.targetLanguage),
        'formality': 'default',
        'preserve_formatting': true,
      };

      // Add glossary if available (would need to be created beforehand)
      // For now, glossary support is handled separately

      // Make API request
      final response = await _dio.post(
        '/translate',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      // Parse response
      final llmResponse = _parseResponse(
        response.data,
        request,
        startTime,
      );

      return Ok(llmResponse);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Unexpected error: $e',
        providerCode: providerCode,
        code: 'UNEXPECTED_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  int estimateTokens(String text) {
    // DeepL uses characters, not tokens
    return _tokenCalculator.calculateCharacterCount({' ': text});
  }

  @override
  int estimateRequestTokens(LlmRequest request) {
    // For DeepL, return character count
    return _tokenCalculator.calculateCharacterCount(request.texts);
  }

  @override
  Future<Result<bool, LlmProviderException>> validateApiKey(
    String apiKey, {
    String? model,
  }) async {
    // DeepL doesn't use models, so ignore the model parameter
    try {
      // Update base URL based on API key type (FREE vs PRO)
      _updateBaseUrl(apiKey);

      // DeepL has a usage endpoint for checking API key and quota
      final response = await _dio.get(
        '/usage',
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      return Ok(response.statusCode == 200);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return Err(LlmAuthenticationException(
          'Invalid API key',
          providerCode: providerCode,
        ));
      }
      return Err(_handleDioException(e));
    } catch (e) {
      return Err(LlmProviderException(
        'Failed to validate API key: $e',
        providerCode: providerCode,
        code: 'VALIDATION_ERROR',
      ));
    }
  }

  @override
  bool get supportsStreaming => false;

  @override
  Stream<Result<String, LlmProviderException>> translateStreaming(
    LlmRequest request,
    String apiKey,
  ) {
    // DeepL doesn't support streaming
    throw LlmUnsupportedOperationException(
      'DeepL does not support streaming translation',
      operation: 'translateStreaming',
    );
  }

  @override
  Duration calculateRetryDelay(LlmRateLimitException exception) {
    // DeepL returns retry-after in seconds
    if (exception.retryAfterSeconds != null) {
      return Duration(seconds: exception.retryAfterSeconds!);
    }

    // Default exponential backoff
    return const Duration(seconds: 60);
  }

  @override
  Future<Result<bool, LlmProviderException>> isAvailable() async {
    try {
      // Check if service is reachable
      final response = await _dio.get(
        '/usage',
        options: Options(
          validateStatus: (status) => status != null,
        ),
      );
      // Any response (even 403 for missing auth) means service is available
      return Ok(response.statusCode! < 500);
    } catch (e) {
      return Err(LlmNetworkException(
        'Service unavailable',
        providerCode: providerCode,
      ));
    }
  }

  @override
  Future<Result<RateLimitStatus?, LlmProviderException>> getRateLimitStatus(
    String apiKey,
  ) async {
    // DeepL doesn't expose rate limit info in headers
    // But we can get usage information
    try {
      // Update base URL based on API key type (FREE vs PRO)
      _updateBaseUrl(apiKey);

      final response = await _dio.get(
        '/usage',
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        // DeepL returns character count and limit
        final characterCount = data['character_count'] as int?;
        final characterLimit = data['character_limit'] as int?;

        if (characterCount != null && characterLimit != null) {
          return Ok(RateLimitStatus(
            remainingTokens: characterLimit - characterCount,
            totalTokens: characterLimit,
          ));
        }
      }

      return const Ok(null);
    } catch (e) {
      return const Ok(null);
    }
  }

  @override
  Future<Result<List<LlmModelInfo>, LlmProviderException>> fetchModels(
    String apiKey,
  ) async {
    // DeepL doesn't have multiple models, so return an empty list
    return const Ok([]);
  }

  /// Parse API response
  LlmResponse _parseResponse(
    Map<String, dynamic> data,
    LlmRequest request,
    DateTime startTime,
  ) {
    try {
      // Extract translations array
      final translationsList = data['translations'] as List;

      if (translationsList.length != request.texts.length) {
        throw FormatException(
          'Response contains ${translationsList.length} translations '
          'but expected ${request.texts.length}',
        );
      }

      // Map translations back to original keys
      final translations = <String, String>{};
      final keys = request.texts.keys.toList();

      for (var i = 0; i < translationsList.length; i++) {
        final translation = translationsList[i] as Map<String, dynamic>;
        final translatedText = translation['text'] as String;
        translations[keys[i]] = translatedText;
      }

      // Calculate character count
      int totalCharacters = 0;
      for (final text in request.texts.values) {
        totalCharacters += text.length;
      }

      // Calculate processing time
      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      return LlmResponse(
        requestId: request.requestId,
        translations: translations,
        providerCode: providerCode,
        modelName: 'deepl-pro', // DeepL doesn't have different models
        inputTokens: totalCharacters, // Characters, not tokens
        outputTokens: 0, // DeepL doesn't charge for output separately
        totalTokens: totalCharacters,
        processingTimeMs: processingTime,
        timestamp: DateTime.now(),
        finishReason: 'completed',
      );
    } catch (e, stackTrace) {
      throw LlmResponseParseException(
        'Failed to parse response: $e',
        providerCode: providerCode,
        rawResponse: data.toString(),
        stackTrace: stackTrace,
      );
    }
  }

  /// Map language codes to DeepL format
  ///
  /// DeepL uses specific language codes (e.g., "EN", "DE", "FR")
  /// Some languages have variants (e.g., "EN-US", "EN-GB", "PT-BR", "PT-PT")
  String _mapLanguageCode(String isoCode) {
    // Map common ISO 639-1 codes to DeepL codes
    final mapping = {
      // European languages
      'en': 'EN', // English (will use EN-US by default)
      'en-us': 'EN-US', // American English
      'en-gb': 'EN-GB', // British English
      'de': 'DE', // German
      'fr': 'FR', // French
      'es': 'ES', // Spanish
      'it': 'IT', // Italian
      'nl': 'NL', // Dutch
      'pl': 'PL', // Polish
      'pt': 'PT-BR', // Portuguese (Brazilian by default)
      'pt-br': 'PT-BR', // Brazilian Portuguese
      'pt-pt': 'PT-PT', // European Portuguese
      'ru': 'RU', // Russian

      // Nordic languages
      'da': 'DA', // Danish
      'fi': 'FI', // Finnish
      'sv': 'SV', // Swedish
      'nb': 'NB', // Norwegian (Bokmål)

      // Eastern European languages
      'bg': 'BG', // Bulgarian
      'cs': 'CS', // Czech
      'et': 'ET', // Estonian
      'hu': 'HU', // Hungarian
      'lv': 'LV', // Latvian
      'lt': 'LT', // Lithuanian
      'ro': 'RO', // Romanian
      'sk': 'SK', // Slovak
      'sl': 'SL', // Slovenian

      // Other European languages
      'el': 'EL', // Greek
      'uk': 'UK', // Ukrainian
      'tr': 'TR', // Turkish

      // Asian languages
      'ja': 'JA', // Japanese
      'zh': 'ZH', // Chinese (Simplified)
      'zh-hans': 'ZH', // Chinese (Simplified)
      'ko': 'KO', // Korean
      'id': 'ID', // Indonesian

      // Arabic
      'ar': 'AR', // Arabic
    };

    final lowerCode = isoCode.toLowerCase();
    return mapping[lowerCode] ?? isoCode.toUpperCase();
  }

  /// Handle Dio exceptions
  LlmProviderException _handleDioException(DioException e) {
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
        providerCode: providerCode,
      );
    }

    // Handle quota exceeded (DeepL-specific status code)
    if (statusCode == 456) {
      return LlmQuotaException(
        'Quota exceeded: $errorMessage',
        providerCode: providerCode,
      );
    }

    // Handle rate limit errors
    if (statusCode == 429) {
      final retryAfter = e.response?.headers.value('retry-after');
      return LlmRateLimitException(
        'Too many requests: $errorMessage',
        providerCode: providerCode,
        retryAfterSeconds: retryAfter != null ? int.tryParse(retryAfter) : null,
      );
    }

    // Handle invalid request errors
    if (statusCode == 400) {
      return LlmInvalidRequestException(
        'Invalid request: $errorMessage',
        providerCode: providerCode,
      );
    }

    // Handle unsupported language errors
    if (statusCode == 404) {
      return LlmInvalidRequestException(
        'Unsupported language pair: $errorMessage',
        providerCode: providerCode,
      );
    }

    // Handle other 4xx errors
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return LlmInvalidRequestException(
        errorMessage,
        providerCode: providerCode,
      );
    }

    // Handle server errors
    if (statusCode != null && statusCode >= 500) {
      return LlmServerException(
        'Server error: $errorMessage',
        providerCode: providerCode,
        statusCode: statusCode,
      );
    }

    // Handle timeout errors
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return LlmNetworkException(
        'Request timeout: ${e.message}',
        providerCode: providerCode,
      );
    }

    // Handle connection errors
    if (e.type == DioExceptionType.connectionError) {
      return LlmNetworkException(
        'Connection failed: ${e.message}',
        providerCode: providerCode,
      );
    }

    // Default network error
    return LlmNetworkException(
      'Network error: ${e.message ?? errorMessage}',
      providerCode: providerCode,
    );
  }

  /// Create glossary for DeepL
  ///
  /// DeepL supports custom glossaries for consistent terminology.
  /// Glossaries are created once and can be reused across translations.
  ///
  /// Returns the glossary ID which can be used in translate requests.
  Future<Result<String, LlmProviderException>> createGlossary({
    required String apiKey,
    required String name,
    required String targetLang,
    required Map<String, String> entries,
  }) async {
    try {
      // Format glossary entries as TSV (tab-separated values)
      final entriesString = entries.entries
          .map((e) => '${e.key}\t${e.value}')
          .join('\n');

      final payload = {
        'name': name,
        'target_lang': _mapLanguageCode(targetLang),
        'entries': entriesString,
        'entries_format': 'tsv',
      };

      final response = await _dio.post(
        '/glossaries',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final glossaryId = data['glossary_id'] as String;

      return Ok(glossaryId);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Failed to create glossary: $e',
        providerCode: providerCode,
        code: 'GLOSSARY_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// List all glossaries for the API key
  Future<Result<List<Map<String, dynamic>>, LlmProviderException>> listGlossaries({
    required String apiKey,
  }) async {
    try {
      final response = await _dio.get(
        '/glossaries',
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final glossaries = data['glossaries'] as List;

      return Ok(glossaries.cast<Map<String, dynamic>>());
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Failed to list glossaries: $e',
        providerCode: providerCode,
        code: 'GLOSSARY_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Delete a glossary
  Future<Result<void, LlmProviderException>> deleteGlossary({
    required String apiKey,
    required String glossaryId,
  }) async {
    try {
      await _dio.delete(
        '/glossaries/$glossaryId',
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      return const Ok(null);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Failed to delete glossary: $e',
        providerCode: providerCode,
        code: 'GLOSSARY_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Translate with a specific glossary
  ///
  /// The glossary must be created beforehand using [createGlossary].
  Future<Result<LlmResponse, LlmProviderException>> translateWithGlossary({
    required LlmRequest request,
    required String apiKey,
    required String glossaryId,
  }) async {
    final startTime = DateTime.now();

    try {
      final texts = request.texts.values.toList();

      final payload = {
        'text': texts,
        'target_lang': _mapLanguageCode(request.targetLanguage),
        'glossary_id': glossaryId,
        'formality': 'default',
        'preserve_formatting': true,
      };

      final response = await _dio.post(
        '/translate',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      final llmResponse = _parseResponse(
        response.data,
        request,
        startTime,
      );

      return Ok(llmResponse);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Unexpected error: $e',
        providerCode: providerCode,
        code: 'UNEXPECTED_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Get supported languages
  ///
  /// Returns list of languages supported by DeepL for source and target.
  Future<Result<Map<String, List<String>>, LlmProviderException>> getSupportedLanguages({
    required String apiKey,
  }) async {
    try {
      // Update base URL based on API key type (FREE vs PRO)
      _updateBaseUrl(apiKey);

      // Get source languages
      final sourceResponse = await _dio.get(
        '/languages',
        queryParameters: {'type': 'source'},
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      // Get target languages
      final targetResponse = await _dio.get(
        '/languages',
        queryParameters: {'type': 'target'},
        options: Options(
          headers: {
            'Authorization': 'DeepL-Auth-Key $apiKey',
          },
        ),
      );

      final sourceLanguages = (sourceResponse.data as List)
          .map((lang) => (lang as Map<String, dynamic>)['language'] as String)
          .toList();

      final targetLanguages = (targetResponse.data as List)
          .map((lang) => (lang as Map<String, dynamic>)['language'] as String)
          .toList();

      return Ok({
        'source': sourceLanguages,
        'target': targetLanguages,
      });
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Failed to get supported languages: $e',
        providerCode: providerCode,
        code: 'API_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }
}
