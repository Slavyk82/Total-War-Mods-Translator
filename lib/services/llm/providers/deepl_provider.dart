import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';
import 'package:twmt/services/llm/utils/deepl_api_client.dart';
import 'package:twmt/services/llm/utils/deepl_language_mapper.dart';
import 'package:twmt/services/llm/utils/deepl_text_processor.dart';

/// DeepL provider implementation for the ILlmProvider interface.
///
/// API Documentation: https://developers.deepl.com/docs/api-reference
/// - No model selection - single translation engine
/// - Character-based pricing (not token-based)
/// - Rate Limits: 100 requests/min default
///
/// This provider delegates to:
/// - [DeepLApiClient] for HTTP operations and error handling
/// - [DeepLLanguageMapper] for language code conversion
/// - [DeepLTextProcessor] for text preprocessing/postprocessing
class DeepLProvider implements ILlmProvider {
  final DeepLApiClient _apiClient;
  final DeepLLanguageMapper _languageMapper;
  final DeepLTextProcessor _textProcessor;
  final TokenCalculator _tokenCalculator;

  @override
  final String providerCode = 'deepl';

  @override
  final String providerName = 'DeepL';

  @override
  final LlmProviderConfig config = LlmProviderConfig.deepl;

  DeepLProvider({
    Dio? dio,
    String? apiKey,
    DeepLApiClient? apiClient,
    DeepLLanguageMapper? languageMapper,
    DeepLTextProcessor? textProcessor,
    TokenCalculator? tokenCalculator,
  })  : _apiClient = apiClient ?? DeepLApiClient(dio: dio),
        _languageMapper = languageMapper ?? const DeepLLanguageMapper(),
        _textProcessor = textProcessor ?? const DeepLTextProcessor(),
        _tokenCalculator = tokenCalculator ?? TokenCalculator();

  @override
  Future<Result<LlmResponse, LlmProviderException>> translate(
    LlmRequest request,
    String apiKey, {
    CancelToken? cancelToken,
  }) async {
    final startTime = DateTime.now();

    return _apiClient.wrapRequest(() async {
      // Preprocess texts to convert \n to XML placeholders
      final texts = _textProcessor.preprocessBatch(request.texts.values);

      // Make API request
      final response = await _apiClient.translate(
        texts: texts,
        targetLang: _languageMapper.mapLanguageCode(request.targetLanguage),
        apiKey: apiKey,
        cancelToken: cancelToken,
      );

      // Parse and return response
      return _parseResponse(response.data, request, startTime);
    });
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
    return _apiClient.wrapRequest(() async {
      final response = await _apiClient.getUsage(apiKey);
      return response.statusCode == 200;
    });
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
      final response = await _apiClient.checkAvailability();
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
    return _apiClient.wrapRequest(() async {
      final response = await _apiClient.getUsage(apiKey);
      final data = response.data as Map<String, dynamic>?;

      if (data != null) {
        final characterCount = data['character_count'] as int?;
        final characterLimit = data['character_limit'] as int?;

        if (characterCount != null && characterLimit != null) {
          return RateLimitStatus(
            remainingTokens: characterLimit - characterCount,
            totalTokens: characterLimit,
          );
        }
      }
      return null;
    });
  }

  // ===========================================================================
  // Response Parsing
  // ===========================================================================

  /// Parse API response into [LlmResponse].
  LlmResponse _parseResponse(
    Map<String, dynamic> data,
    LlmRequest request,
    DateTime startTime,
  ) {
    try {
      final translationsList = data['translations'] as List;

      if (translationsList.isEmpty && request.texts.isNotEmpty) {
        final sourceTexts = request.texts.values.toList();
        throw LlmContentFilteredException(
          'DeepL returned no translations. The content may have been filtered '
          'or is not supported. Try using a different provider.',
          providerCode: providerCode,
          filteredTexts: sourceTexts,
          finishReason: 'empty_response',
        );
      }

      if (translationsList.length != request.texts.length) {
        throw FormatException(
          'Response contains ${translationsList.length} translations '
          'but expected ${request.texts.length}',
        );
      }

      // Map translations back to original keys
      final translations = <String, String>{};
      final keys = request.texts.keys.toList();
      var emptyCount = 0;

      for (var i = 0; i < translationsList.length; i++) {
        final translation = translationsList[i] as Map<String, dynamic>;
        final translatedText = translation['text'] as String;
        // Postprocess to restore \n from XML placeholders
        translations[keys[i]] = _textProcessor.postprocessText(translatedText);
        if (translatedText.trim().isEmpty) {
          emptyCount++;
        }
      }

      // If all translations are empty, treat as content filtered
      if (emptyCount == translationsList.length && translationsList.isNotEmpty) {
        final sourceTexts = request.texts.values.toList();
        throw LlmContentFilteredException(
          'DeepL returned empty translations for all texts. The content may '
          'have been filtered. Try using a different provider.',
          providerCode: providerCode,
          filteredTexts: sourceTexts,
          finishReason: 'all_empty',
        );
      }

      // Calculate character count
      int totalCharacters = 0;
      for (final text in request.texts.values) {
        totalCharacters += text.length;
      }

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      return LlmResponse(
        requestId: request.requestId,
        translations: translations,
        providerCode: providerCode,
        modelName: request.modelName ?? 'deepl',
        inputTokens: totalCharacters, // Characters, not tokens
        outputTokens: 0, // DeepL doesn't charge for output separately
        totalTokens: totalCharacters,
        processingTimeMs: processingTime,
        timestamp: DateTime.now(),
        finishReason: 'completed',
      );
    } on LlmContentFilteredException {
      rethrow;
    } catch (e, stackTrace) {
      throw LlmResponseParseException(
        'Failed to parse response: $e',
        providerCode: providerCode,
        rawResponse: data.toString(),
        stackTrace: stackTrace,
      );
    }
  }

  // ===========================================================================
  // Glossary Operations
  // ===========================================================================

  /// Create glossary for DeepL.
  ///
  /// DeepL supports custom glossaries for consistent terminology.
  /// Returns the glossary ID which can be used in translate requests.
  Future<Result<String, LlmProviderException>> createGlossary({
    required String apiKey,
    required String name,
    required String targetLang,
    required Map<String, String> entries,
  }) async {
    return _apiClient.wrapRequest(() async {
      // Format glossary entries as TSV (tab-separated values)
      final entriesString = entries.entries
          .map((e) => '${e.key}\t${e.value}')
          .join('\n');

      final response = await _apiClient.createGlossary(
        name: name,
        targetLang: _languageMapper.mapLanguageCode(targetLang),
        entries: entriesString,
        apiKey: apiKey,
      );

      final data = response.data as Map<String, dynamic>;
      return data['glossary_id'] as String;
    });
  }

  /// List all glossaries for the API key.
  Future<Result<List<Map<String, dynamic>>, LlmProviderException>> listGlossaries({
    required String apiKey,
  }) async {
    return _apiClient.wrapRequest(() async {
      final response = await _apiClient.listGlossaries(apiKey);
      final data = response.data as Map<String, dynamic>;
      final glossaries = data['glossaries'] as List;
      return glossaries.cast<Map<String, dynamic>>();
    });
  }

  /// Delete a glossary.
  Future<Result<void, LlmProviderException>> deleteGlossary({
    required String apiKey,
    required String glossaryId,
  }) async {
    return _apiClient.wrapRequest(() async {
      await _apiClient.deleteGlossary(
        glossaryId: glossaryId,
        apiKey: apiKey,
      );
    });
  }

  /// Translate with a specific glossary.
  ///
  /// The glossary must be created beforehand using [createGlossary].
  ///
  /// **Important**: DeepL requires both `source_lang` and `target_lang` to be
  /// explicitly specified when using a glossary.
  Future<Result<LlmResponse, LlmProviderException>> translateWithGlossary({
    required LlmRequest request,
    required String apiKey,
    required String glossaryId,
  }) async {
    final startTime = DateTime.now();

    // Validate source language is provided (required for glossary)
    if (request.sourceLanguage == null || request.sourceLanguage!.isEmpty) {
      return Err(LlmInvalidRequestException(
        'source_lang is required when using a DeepL glossary',
        providerCode: providerCode,
      ));
    }

    return _apiClient.wrapRequest(() async {
      final texts = _textProcessor.preprocessBatch(request.texts.values);

      final response = await _apiClient.translate(
        texts: texts,
        sourceLang: _languageMapper.mapLanguageCode(request.sourceLanguage!),
        targetLang: _languageMapper.mapLanguageCode(request.targetLanguage),
        glossaryId: glossaryId,
        apiKey: apiKey,
      );

      return _parseResponse(response.data, request, startTime);
    });
  }

  /// Get supported languages from DeepL API.
  ///
  /// Returns map with 'source' and 'target' keys containing language codes.
  Future<Result<Map<String, List<String>>, LlmProviderException>> getSupportedLanguages({
    required String apiKey,
  }) async {
    return _apiClient.wrapRequest(() async {
      // Get source languages
      final sourceResponse = await _apiClient.getLanguages(
        apiKey: apiKey,
        type: 'source',
      );

      // Get target languages
      final targetResponse = await _apiClient.getLanguages(
        apiKey: apiKey,
        type: 'target',
      );

      final sourceLanguages = (sourceResponse.data as List)
          .map((lang) => (lang as Map<String, dynamic>)['language'] as String)
          .toList();

      final targetLanguages = (targetResponse.data as List)
          .map((lang) => (lang as Map<String, dynamic>)['language'] as String)
          .toList();

      return {
        'source': sourceLanguages,
        'target': targetLanguages,
      };
    });
  }
}
