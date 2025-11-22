import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/models/llm_model_info.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// Anthropic (Claude) provider implementation
///
/// API Documentation: https://docs.anthropic.com/claude/reference/
/// Models: claude-3-5-sonnet-20241022 (recommended), claude-3-opus-20240229
/// Rate Limits: 50 RPM default (configurable)
class AnthropicProvider implements ILlmProvider {
  final Dio _dio;
  final TokenCalculator _tokenCalculator = TokenCalculator();

  @override
  final String providerCode = 'anthropic';

  @override
  final String providerName = 'Anthropic (Claude)';

  @override
  final LlmProviderConfig config = LlmProviderConfig.anthropic;

  AnthropicProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: LlmProviderConfig.anthropic.apiBaseUrl,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 120),
              headers: {
                'Content-Type': 'application/json',
                'anthropic-version': '2023-06-01',
              },
            ));

  @override
  Future<Result<LlmResponse, LlmProviderException>> translate(
    LlmRequest request,
    String apiKey,
  ) async {
    final startTime = DateTime.now();

    try {
      // Build request payload
      final payload = _buildRequestPayload(request);

      // Make API request
      final response = await _dio.post(
        '/messages',
        data: payload,
        options: Options(
          headers: {
            'x-api-key': apiKey,
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
    return _tokenCalculator.calculateAnthropicTokens(text);
  }

  @override
  int estimateRequestTokens(LlmRequest request) {
    return _tokenCalculator.estimateAnthropicRequestTokens(request);
  }

  @override
  Future<Result<bool, LlmProviderException>> validateApiKey(
    String apiKey, {
    String? model,
  }) async {
    final modelToUse = model ?? config.defaultModel;

    try {
      final requestData = {
        'model': modelToUse,
        'max_tokens': 10,
        'messages': [
          {
            'role': 'user',
            'content': 'Hi',
          }
        ],
      };

      // Make a minimal request to validate API key
      // Using minimal tokens for fast validation (10 is minimum for Anthropic)
      final response = await _dio.post(
        '/messages',
        data: requestData,
        options: Options(
          headers: {
            'x-api-key': apiKey,
          },
        ),
      );

      final isSuccess = response.statusCode == 200;

      return Ok(isSuccess);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return Err(LlmAuthenticationException(
          'Invalid API key',
          providerCode: providerCode,
        ));
      }
      final error = _handleDioException(e);
      return Err(error);
    } catch (e, stackTrace) {
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
        '/messages',
        data: payload,
        options: Options(
          headers: {
            'x-api-key': apiKey,
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
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final eventType = json['type'] as String?;

            // Extract text deltas from content blocks
            if (eventType == 'content_block_delta') {
              final delta = json['delta'] as Map<String, dynamic>?;
              if (delta != null && delta['type'] == 'text_delta') {
                final text = delta['text'] as String?;
                if (text != null && text.isNotEmpty) {
                  yield Ok(text);
                }
              }
            }
            // Handle stream completion
            else if (eventType == 'message_stop') {
              break;
            }
            // Handle errors in stream
            else if (eventType == 'error') {
              final error = json['error'] as Map<String, dynamic>?;
              final errorMessage = error?['message'] as String? ?? 'Unknown streaming error';
              yield Err(LlmProviderException(
                errorMessage,
                providerCode: providerCode,
                code: 'STREAMING_ERROR',
              ));
              break;
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
    // Use Retry-After header if provided
    if (exception.retryAfterSeconds != null) {
      return Duration(seconds: exception.retryAfterSeconds!);
    }

    // Default exponential backoff
    return const Duration(seconds: 60);
  }

  @override
  Future<Result<bool, LlmProviderException>> isAvailable() async {
    try {
      // Anthropic API doesn't have a health endpoint
      // Try a lightweight request to root - will return 404 but confirms API is reachable
      final response = await _dio.get(
        '/',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
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
    // Anthropic doesn't expose rate limit info in response headers
    // Would need to track rate limits client-side
    return const Ok(null);
  }

  @override
  Future<Result<List<LlmModelInfo>, LlmProviderException>> fetchModels(
    String apiKey,
  ) async {
    try {
      final response = await _dio.get(
        '/models',
        options: Options(
          headers: {
            'x-api-key': apiKey,
          },
        ),
      );

      // Parse response
      final data = response.data as Map<String, dynamic>;
      final modelsData = data['data'] as List;

      final models = modelsData.map((modelData) {
        final modelMap = modelData as Map<String, dynamic>;
        return LlmModelInfo(
          id: modelMap['id'] as String,
          displayName: modelMap['display_name'] as String?,
          createdAt: modelMap['created_at'] != null
              ? DateTime.tryParse(modelMap['created_at'] as String)
              : null,
          type: modelMap['type'] as String?,
        );
      }).toList();

      return Ok(models);
    } on DioException catch (e) {
      return Err(_handleDioException(e));
    } catch (e, stackTrace) {
      return Err(LlmProviderException(
        'Failed to fetch models: $e',
        providerCode: providerCode,
        code: 'FETCH_MODELS_ERROR',
        stackTrace: stackTrace,
      ));
    }
  }

  /// Build request payload for Anthropic API
  Map<String, dynamic> _buildRequestPayload(LlmRequest request) {
    // Build system prompt
    final systemPrompt = _buildSystemPrompt(request);

    // Build user message with texts to translate
    final userMessage = _buildUserMessage(request);

    final modelToUse = request.modelName ?? config.defaultModel;

    // DEBUG: Log final model selection
    print('[DEBUG] AnthropicProvider._buildRequestPayload:');
    print('[DEBUG]   - request.modelName: ${request.modelName}');
    print('[DEBUG]   - config.defaultModel: ${config.defaultModel}');
    print('[DEBUG]   - Final model to use: $modelToUse');

    return {
      'model': modelToUse,
      'max_tokens': request.maxTokens ?? 4096,
      'temperature': request.temperature,
      'system': systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content': userMessage,
        }
      ],
    };
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

    // Ensure JSON output format
    parts.add('\n\nYou must respond with ONLY a valid JSON object. '
        'No markdown code blocks, no explanations, just the raw JSON object.');

    return parts.join();
  }

  /// Build user message with translation request
  String _buildUserMessage(LlmRequest request) {
    final parts = <String>[];

    // Add few-shot examples if provided
    if (request.fewShotExamples != null && request.fewShotExamples!.isNotEmpty) {
      parts.add('## Examples\n${_formatExamples(request.fewShotExamples!)}');
    }

    // Add texts to translate
    parts.add('## Translation Task');
    parts.add('Target Language: ${request.targetLanguage}');
    parts.add('\nTranslate the following texts. Preserve the keys, translate only the values:');
    parts.add('\n${jsonEncode(request.texts)}');
    parts.add('\nReturn ONLY a JSON object with the same keys and translated values. No markdown, no code blocks.');

    return parts.join('\n');
  }

  /// Format glossary terms
  String _formatGlossary(Map<String, String> glossary) {
    return glossary.entries
        .map((e) => '- "${e.key}" → "${e.value}" (preserve exactly)')
        .join('\n');
  }

  /// Format few-shot examples
  String _formatExamples(List<TranslationExample> examples) {
    return examples
        .asMap()
        .entries
        .map((e) => 'Example ${e.key + 1}:\nSource: ${e.value.source}\nTarget: ${e.value.target}')
        .join('\n\n');
  }

  /// Parse API response
  LlmResponse _parseResponse(
    Map<String, dynamic> data,
    LlmRequest request,
    DateTime startTime,
  ) {
    try {
      // Extract content
      final content = data['content'] as List;
      final textBlock = content.firstWhere(
        (block) => block['type'] == 'text',
        orElse: () => {'text': ''},
      );
      final responseText = textBlock['text'] as String;

      // Parse JSON response
      final translations = _parseTranslations(responseText, request);

      // Extract token usage
      final usage = data['usage'] as Map<String, dynamic>;
      final inputTokens = usage['input_tokens'] as int;
      final outputTokens = usage['output_tokens'] as int;

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
        finishReason: data['stop_reason'] as String?,
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

  /// Parse translations from response text
  ///
  /// Handles multiple formats:
  /// 1. Plain JSON object: {"key1": "value1", "key2": "value2"}
  /// 2. Array format: {"translations": [{"key": "key1", "translation": "value1"}]}
  /// 3. JSON wrapped in markdown code blocks
  /// 4. JSON with surrounding text
  Map<String, String> _parseTranslations(String responseText, LlmRequest request) {
    try {
      String jsonText = responseText.trim();

      // Try to extract JSON from markdown code block
      final markdownMatch = RegExp(
        r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
        multiLine: true,
      ).firstMatch(jsonText);

      if (markdownMatch != null) {
        jsonText = markdownMatch.group(1)!;
      } else {
        // Try to find raw JSON object in the text
        final jsonMatch = RegExp(
          r'\{[\s\S]*\}',
          multiLine: true,
        ).firstMatch(jsonText);

        if (jsonMatch != null) {
          jsonText = jsonMatch.group(0)!;
        }
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

      // Validate that all requested keys are present
      final missingKeys = request.texts.keys.where(
        (key) => !translations.containsKey(key),
      ).toList();

      if (missingKeys.isNotEmpty) {
        throw FormatException(
          'Missing translations for keys: ${missingKeys.join(", ")}',
        );
      }

      return translations;
    } catch (e) {
      throw LlmResponseParseException(
        'Failed to parse translations from response: $e',
        providerCode: providerCode,
        rawResponse: responseText,
      );
    }
  }

  /// Handle Dio exceptions
  LlmProviderException _handleDioException(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;

    // Extract error details from Anthropic error response
    String errorMessage = 'Unknown error';
    String? errorType;

    if (responseData is Map<String, dynamic>) {
      final error = responseData['error'] as Map<String, dynamic>?;
      if (error != null) {
        errorMessage = error['message'] as String? ?? errorMessage;
        errorType = error['type'] as String?;
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
      final retryAfter = e.response?.headers.value('retry-after');
      return LlmRateLimitException(
        'Rate limit exceeded: $errorMessage',
        providerCode: providerCode,
        retryAfterSeconds: retryAfter != null ? int.tryParse(retryAfter) : null,
      );
    }

    // Handle quota/billing errors
    if (statusCode == 402 || errorType == 'insufficient_quota') {
      return LlmQuotaException(
        'Quota exceeded: $errorMessage',
        providerCode: providerCode,
      );
    }

    // Handle invalid request errors
    if (statusCode == 400) {
      // Check for token limit errors
      if (errorType == 'invalid_request_error' &&
          errorMessage.toLowerCase().contains('token')) {
        return LlmTokenLimitException(
          errorMessage,
          providerCode: providerCode,
        );
      }

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
