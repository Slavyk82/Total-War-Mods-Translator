import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// DeepSeek provider implementation
///
/// API Documentation: https://api-docs.deepseek.com/
/// Uses OpenAI-compatible API format with some differences:
/// - Base URL: https://api.deepseek.com
/// - Uses max_tokens parameter (not max_completion_tokens)
/// - Model: deepseek-chat (DeepSeek-V3.2)
/// - Max output: Default 4K, Maximum 8K tokens
class DeepSeekProvider implements ILlmProvider {
  final Dio _dio;
  final TokenCalculator _tokenCalculator = TokenCalculator();

  @override
  final String providerCode = 'deepseek';

  @override
  final String providerName = 'DeepSeek';

  @override
  final LlmProviderConfig config = LlmProviderConfig.deepseek;

  DeepSeekProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: LlmProviderConfig.deepseek.apiBaseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Content-Type': 'application/json',
              },
            ));

  @override
  Future<Result<LlmResponse, LlmProviderException>> translate(
    LlmRequest request,
    String apiKey, {
    CancelToken? cancelToken,
  }) async {
    final startTime = DateTime.now();

    try {
      // Build request payload
      final payload = _buildRequestPayload(request);

      // Make API request
      final response = await _dio.post(
        '/chat/completions',
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
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
    } on LlmProviderException catch (e) {
      return Err(e);
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
    return _tokenCalculator.calculateTokens(text);
  }

  @override
  int estimateRequestTokens(LlmRequest request) {
    return _tokenCalculator.estimateRequestTokens(request);
  }

  @override
  Future<Result<bool, LlmProviderException>> validateApiKey(
    String apiKey, {
    String? model,
  }) async {
    try {
      // Make a minimal request to validate API key
      final payload = <String, dynamic>{
        'model': model ?? 'deepseek-chat',
        'messages': [
          {'role': 'user', 'content': 'Hi'}
        ],
        'max_tokens': 10,
      };

      final response = await _dio.post(
        '/chat/completions',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        ),
      );

      return Ok(response.statusCode == 200);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
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
  bool get supportsStreaming => true;

  @override
  Stream<Result<String, LlmProviderException>> translateStreaming(
    LlmRequest request,
    String apiKey,
  ) async* {
    try {
      final payload = _buildRequestPayload(request);
      payload['stream'] = true;

      final response = await _dio.post(
        '/chat/completions',
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          responseType: ResponseType.stream,
        ),
      );

      // Process Server-Sent Events (SSE) stream
      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);

        // Process complete lines
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // Keep incomplete line in buffer

        for (final line in lines) {
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          final data = line.substring(6).trim();

          // Check for stream end marker
          if (data == '[DONE]') {
            break;
          }

          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;

            // Extract content delta from choices
            final choices = json['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final delta = choices[0]['delta'] as Map<String, dynamic>?;
              if (delta != null) {
                final content = delta['content'] as String?;
                if (content != null && content.isNotEmpty) {
                  yield Ok(content);
                }
              }

              // Check for finish reason
              final finishReason = choices[0]['finish_reason'] as String?;
              if (finishReason != null && finishReason != 'null') {
                break;
              }
            }
          } catch (e) {
            // Skip malformed JSON chunks
            continue;
          }
        }
      }
    } on DioException catch (e) {
      yield Err(_handleDioException(e));
    } catch (e, stackTrace) {
      yield Err(LlmProviderException(
        'Streaming error: $e',
        providerCode: providerCode,
        code: 'STREAMING_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  @override
  Duration calculateRetryDelay(LlmRateLimitException exception) {
    // Use retry-after header if provided
    if (exception.retryAfterSeconds != null) {
      return Duration(seconds: exception.retryAfterSeconds!);
    }

    // Default exponential backoff
    return const Duration(seconds: 60);
  }

  @override
  Future<Result<bool, LlmProviderException>> isAvailable() async {
    try {
      // DeepSeek doesn't have a dedicated health check endpoint
      // Try a lightweight request to verify connectivity
      final response = await _dio.get(
        '/models',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return Ok(response.statusCode == 200);
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
    // DeepSeek returns rate limit info in response headers
    // We need to track it from response headers
    return const Ok(null);
  }

  /// Build request payload for DeepSeek API
  Map<String, dynamic> _buildRequestPayload(LlmRequest request) {
    final messages = <Map<String, String>>[];

    // System message
    messages.add({
      'role': 'system',
      'content': _buildSystemPrompt(request),
    });

    // Few-shot examples (if provided)
    if (request.fewShotExamples != null && request.fewShotExamples!.isNotEmpty) {
      for (final example in request.fewShotExamples!) {
        messages.add({
          'role': 'user',
          'content': 'Translate: ${example.source}',
        });
        messages.add({
          'role': 'assistant',
          'content': jsonEncode({example.source: example.target}),
        });
      }
    }

    // User message with translation request
    messages.add({
      'role': 'user',
      'content': _buildUserMessage(request),
    });

    final modelName = request.modelName ?? 'deepseek-chat';
    // DeepSeek default max output is 4K, maximum is 8K
    final maxTokens = request.maxTokens ?? 4096;

    final payload = <String, dynamic>{
      'model': modelName,
      'messages': messages,
      'response_format': {'type': 'json_object'},
      'temperature': request.temperature,
      'max_tokens': maxTokens, // DeepSeek uses max_tokens, not max_completion_tokens
    };

    return payload;
  }

  /// Build system prompt
  String _buildSystemPrompt(LlmRequest request) {
    final parts = <String>[request.systemPrompt];

    if (request.gameContext != null) {
      parts.add('\n\n## Game Context\n${request.gameContext}');
    }

    if (request.projectContext != null) {
      parts.add('\n\n## Project Context\n${request.projectContext}');
    }

    if (request.glossaryTerms != null && request.glossaryTerms!.isNotEmpty) {
      parts.add('\n\n## Glossary Terms\n${_formatGlossary(request.glossaryTerms!)}');
    }

    // Emphasize JSON output format and tag preservation
    parts.add('\n\nCRITICAL: You must preserve ALL formatting tags exactly as they appear in the source text.');
    parts.add('This includes: [[col:red]], [[col:yellow]], [%s], <tags>, etc.');
    parts.add('For {{...}} template expressions: preserve structure/code but you may translate quoted display strings inside.');
    parts.add('IMPORTANT: When translating, use correct hyphenated forms for compound words (e.g., "lui-même", not "luimême" or "lui même").');
    parts.add('\nYou must respond with valid JSON only. '
        'Return a JSON object with the same keys as the input, with translated values.');

    return parts.join();
  }

  /// Build user message
  String _buildUserMessage(LlmRequest request) {
    return 'Translate the following texts to ${request.targetLanguage}. '
        'PRESERVE ALL TAGS AND PLACEHOLDERS EXACTLY.\n'
        'Return ONLY a JSON object with the same keys:\n\n'
        '${jsonEncode(request.texts)}';
  }

  /// Format glossary terms
  String _formatGlossary(Map<String, String> glossary) {
    return glossary.entries
        .map((e) => '- "${e.key}" → "${e.value}" (preserve exactly)')
        .join('\n');
  }

  /// Parse API response
  LlmResponse _parseResponse(
    Map<String, dynamic> data,
    LlmRequest request,
    DateTime startTime,
  ) {
    try {
      // Extract content from first choice
      final choices = data['choices'] as List;
      if (choices.isEmpty) {
        throw const FormatException('No choices in response');
      }

      final choice = choices[0] as Map<String, dynamic>;
      final finishReason = choice['finish_reason'] as String?;
      final message = choice['message'] as Map<String, dynamic>;
      final content = message['content'] as String?;

      // Check for content filtering or empty content
      if (finishReason == 'content_filter' ||
          (content == null || content.trim().isEmpty)) {
        final sourceTexts = request.texts.values.toList();
        throw LlmContentFilteredException(
          'Content blocked by provider moderation. The source text may contain '
          'content that violates the provider\'s usage policies. Try using a '
          'different provider for this content.',
          providerCode: providerCode,
          filteredTexts: sourceTexts,
          finishReason: finishReason ?? 'empty_content',
        );
      }

      // Parse translations
      final translations = _parseTranslations(content, request);

      // Extract token usage with null safety
      final usage = data['usage'] as Map<String, dynamic>? ?? {};
      final inputTokens = usage['prompt_tokens'] as int? ?? 0;
      final outputTokens = usage['completion_tokens'] as int? ?? 0;

      // Calculate processing time
      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      return LlmResponse(
        requestId: request.requestId,
        translations: translations,
        providerCode: providerCode,
        modelName: data['model'] as String,
        inputTokens: inputTokens,
        outputTokens: outputTokens,
        totalTokens: inputTokens + outputTokens,
        processingTimeMs: processingTime,
        timestamp: DateTime.now(),
        finishReason: finishReason,
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

  /// Parse translations from JSON response
  Map<String, String> _parseTranslations(String content, LlmRequest request) {
    try {
      String jsonText = content.trim();

      // Handle edge cases where response might be wrapped in markdown
      final markdownMatch = RegExp(
        r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
        multiLine: true,
      ).firstMatch(jsonText);

      if (markdownMatch != null) {
        jsonText = markdownMatch.group(1)!;
      }

      // Parse JSON
      final dynamic parsed = jsonDecode(jsonText);

      if (parsed is! Map) {
        throw const FormatException('Response is not a JSON object');
      }

      final Map<String, String> translations = {};

      if (parsed.containsKey('translations')) {
        // Array format
        final translationsArray = parsed['translations'];

        if (translationsArray is! List) {
          throw const FormatException('translations field is not an array');
        }

        for (final item in translationsArray) {
          if (item is! Map) continue;

          final key = item['key']?.toString();
          final translation = item['translation']?.toString();

          if (key != null && translation != null) {
            translations[key] = translation;
          }
        }
      } else {
        // Simple key-value format
        parsed.forEach((key, value) {
          translations[key.toString()] = value.toString();
        });
      }

      // Filter out empty string translations
      final emptyKeys = translations.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();

      for (final key in emptyKeys) {
        translations.remove(key);
      }

      // Fail only if no valid translations were parsed at all
      if (translations.isEmpty && request.texts.isNotEmpty) {
        throw FormatException(
          'No valid translations found in response (${emptyKeys.length} empty)',
        );
      }

      return translations;
    } catch (e) {
      throw LlmResponseParseException(
        'Failed to parse translations from response: $e',
        providerCode: providerCode,
        rawResponse: content,
      );
    }
  }

  /// Handle Dio exceptions
  LlmProviderException _handleDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;
    final headers = e.response?.headers;

    // Extract error details from DeepSeek error response
    String errorMessage = 'Unknown error';
    String? errorType;
    String? errorCode;

    if (responseData is Map<String, dynamic>) {
      final error = responseData['error'] as Map<String, dynamic>?;
      if (error != null) {
        errorMessage = error['message'] as String? ?? errorMessage;
        errorType = error['type'] as String?;
        errorCode = error['code'] as String?;
      }
    } else if (responseData != null) {
      errorMessage = responseData.toString();
    }

    // Handle authentication errors
    if (statusCode == 401) {
      return LlmAuthenticationException(
        'Invalid API key: $errorMessage',
        providerCode: providerCode,
      );
    }

    // Handle rate limit errors
    if (statusCode == 429) {
      final retryAfter = headers?.value('retry-after');
      int? retryAfterSeconds;
      if (retryAfter != null) {
        retryAfterSeconds = int.tryParse(retryAfter);
      }

      return LlmRateLimitException(
        'Rate limit exceeded: $errorMessage',
        providerCode: providerCode,
        retryAfterSeconds: retryAfterSeconds,
      );
    }

    // Handle quota/billing errors
    if (statusCode == 402 ||
        errorType == 'insufficient_quota' ||
        errorCode == 'insufficient_quota') {
      return LlmQuotaException(
        'Quota exceeded: $errorMessage',
        providerCode: providerCode,
      );
    }

    // Handle token limit errors
    if (statusCode == 400 &&
        (errorType == 'invalid_request_error' || errorCode == 'context_length_exceeded') &&
        (errorMessage.toLowerCase().contains('token') ||
         errorMessage.toLowerCase().contains('context length'))) {
      return LlmTokenLimitException(
        errorMessage,
        providerCode: providerCode,
      );
    }

    // Handle other invalid request errors
    if (statusCode == 400) {
      return LlmInvalidRequestException(
        errorMessage,
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
}
