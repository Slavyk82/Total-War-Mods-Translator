import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// OpenAI (GPT) provider implementation
///
/// API Documentation: https://platform.openai.com/docs/api-reference
/// Rate Limits: Configurable RPM/TPM per account
///
/// Note: Model capabilities (temperature support, JSON format support, token
/// parameter names) should be stored in the database llm_provider_models table.
/// This provider uses safe defaults that work with most modern models.
class OpenAiProvider implements ILlmProvider {
  final Dio _dio;
  final TokenCalculator _tokenCalculator = TokenCalculator();

  @override
  final String providerCode = 'openai';

  @override
  final String providerName = 'OpenAI';

  @override
  final LlmProviderConfig config = LlmProviderConfig.openai;

  OpenAiProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: LlmProviderConfig.openai.apiBaseUrl,
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
      // Re-return already formatted LLM exceptions (content filter, parse errors, etc.)
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
    if (model == null) {
      return Err(LlmInvalidRequestException(
        'Model is required for OpenAI API key validation',
        providerCode: providerCode,
      ));
    }

    try {
      // Make a minimal request to validate API key
      // Using minimal tokens for fast validation (10 to ensure response)
      final payload = <String, dynamic>{
        'model': model,
        'messages': [
          {'role': 'user', 'content': 'Hi'}
        ],
      };

      // Use max_completion_tokens (modern OpenAI API standard)
      payload['max_completion_tokens'] = 10;

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
      // OpenAI has a models endpoint we can check
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
    // OpenAI returns rate limit info in response headers
    // We would need to make a request to get current status
    // For now, return null to indicate we need to track it from response headers
    return const Ok(null);
  }

  /// Build request payload for OpenAI API
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

    if (request.modelName == null) {
      throw ArgumentError('modelName is required for OpenAI requests');
    }

    final modelName = request.modelName!;
    final maxTokens = request.maxTokens ?? 4096;

    final payload = <String, dynamic>{
      'model': modelName,
      'messages': messages,
      'response_format': {'type': 'json_object'},
      'temperature': request.temperature,
      'max_completion_tokens': maxTokens,
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
        throw FormatException('No choices in response');
      }

      final choice = choices[0] as Map<String, dynamic>;
      final finishReason = choice['finish_reason'] as String?;
      final message = choice['message'] as Map<String, dynamic>;
      final content = message['content'] as String?;

      // Check for content filtering (explicit finish_reason or empty content)
      // OpenAI returns finish_reason: "content_filter" when moderation triggers
      // Some models return empty content instead of explicit filter reason
      if (finishReason == 'content_filter' ||
          (content == null || content.trim().isEmpty)) {
        final sourceTexts = request.texts.values.toList();
        throw LlmContentFilteredException(
          'Content blocked by provider moderation. The source text may contain '
          'content that violates the provider\'s usage policies. Try using a '
          'different provider (e.g., Claude or DeepL) for this content.',
          providerCode: providerCode,
          filteredTexts: sourceTexts,
          finishReason: finishReason ?? 'empty_content',
        );
      }

      // Parse translations
      final translations = _parseTranslations(content, request);

      // Extract token usage
      final usage = data['usage'] as Map<String, dynamic>;
      final inputTokens = usage['prompt_tokens'] as int;
      final outputTokens = usage['completion_tokens'] as int;

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
      // Re-throw content filter exceptions as-is (don't wrap in parse exception)
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
  ///
  /// Handles multiple formats:
  /// 1. Plain JSON object: {"key1": "value1", "key2": "value2"}
  /// 2. Array format: {"translations": [{"key": "key1", "translation": "value1"}]}
  /// 3. JSON wrapped in markdown code blocks
  ///
  /// Returns partial results if some keys are missing (lenient parsing).
  /// The caller should handle retrying missing keys if needed.
  Map<String, String> _parseTranslations(String content, LlmRequest request) {
    try {
      String jsonText = content.trim();

      // OpenAI with json_object format should return pure JSON
      // But handle edge cases where it might wrap in markdown
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
        throw FormatException('Response is not a JSON object');
      }

      // Check if this is the array format: {"translations": [...]}
      final Map<String, String> translations = {};

      if (parsed.containsKey('translations')) {
        // Array format from PromptBuilderService
        final translationsArray = parsed['translations'];

        if (translationsArray is! List) {
          throw FormatException('translations field is not an array');
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

      // Check for missing keys but don't throw - return partial results
      // This allows the caller to handle retrying only the missing keys
      final missingKeys = request.texts.keys.where(
        (key) => !translations.containsKey(key),
      ).toList();

      if (missingKeys.isNotEmpty) {
        // Log warning but continue with partial results
        // ignore: avoid_print
        print('[OpenAI] Warning: LLM response missing ${missingKeys.length} keys: ${missingKeys.take(3).join(", ")}${missingKeys.length > 3 ? "..." : ""}');
      }

      // Fail only if no translations were parsed at all
      if (translations.isEmpty && request.texts.isNotEmpty) {
        throw FormatException(
          'No valid translations found in response',
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

    // Extract error details from OpenAI error response
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
      final rateLimitRemaining = headers?.value('x-ratelimit-remaining-requests');
      final rateLimitTokens = headers?.value('x-ratelimit-remaining-tokens');
      final rateLimitResetRequests = headers?.value('x-ratelimit-reset-requests');

      // Parse retry-after (can be seconds or timestamp)
      int? retryAfterSeconds;
      if (retryAfter != null) {
        retryAfterSeconds = int.tryParse(retryAfter);
        // If parsing failed, it might be an HTTP date - calculate from reset time
        if (retryAfterSeconds == null && rateLimitResetRequests != null) {
          try {
            final resetTime = DateTime.parse(rateLimitResetRequests);
            retryAfterSeconds = resetTime.difference(DateTime.now()).inSeconds;
          } catch (_) {
            // Ignore parsing error
          }
        }
      }

      return LlmRateLimitException(
        'Rate limit exceeded: $errorMessage',
        providerCode: providerCode,
        retryAfterSeconds: retryAfterSeconds,
        rateLimitRpm: rateLimitRemaining != null ? int.tryParse(rateLimitRemaining) : null,
        rateLimitTpm: rateLimitTokens != null ? int.tryParse(rateLimitTokens) : null,
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

    // Handle max_tokens parameter error (model requires max_completion_tokens)
    if (statusCode == 400 &&
        errorMessage.contains('max_tokens') &&
        errorMessage.contains('not supported')) {
      return LlmInvalidRequestException(
        'Model requires max_completion_tokens parameter. Please report this model to update the provider.',
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
