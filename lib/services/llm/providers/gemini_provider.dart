import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// Google Gemini provider implementation
///
/// API Documentation: https://ai.google.dev/gemini-api/docs
/// Models:
/// - gemini-3-pro-preview: Most intelligent model
/// - gemini-3-flash-preview: Fast and cost-efficient
/// Max output: 65,536 tokens
class GeminiProvider implements ILlmProvider {
  final Dio _dio;
  final TokenCalculator _tokenCalculator = TokenCalculator();

  @override
  final String providerCode = 'gemini';

  @override
  final String providerName = 'Google Gemini';

  @override
  final LlmProviderConfig config = LlmProviderConfig.gemini;

  GeminiProvider({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: LlmProviderConfig.gemini.apiBaseUrl,
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
      final modelName = request.modelName ?? 'gemini-3-flash-preview';
      final payload = _buildRequestPayload(request);

      final response = await _dio.post(
        '/models/$modelName:generateContent',
        data: payload,
        cancelToken: cancelToken,
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
          },
        ),
      );

      final llmResponse = _parseResponse(
        response.data,
        request,
        modelName,
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
      final modelName = model ?? 'gemini-3-flash-preview';
      final payload = <String, dynamic>{
        'contents': [
          {
            'parts': [
              {'text': 'Hi'}
            ]
          }
        ],
        'generationConfig': {
          'maxOutputTokens': 10,
        },
      };

      final response = await _dio.post(
        '/models/$modelName:generateContent',
        data: payload,
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
          },
        ),
      );

      return Ok(response.statusCode == 200);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
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
      final modelName = request.modelName ?? 'gemini-3-flash-preview';
      final payload = _buildRequestPayload(request);

      final response = await _dio.post(
        '/models/$modelName:streamGenerateContent?alt=sse',
        data: payload,
        options: Options(
          headers: {
            'x-goog-api-key': apiKey,
          },
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data.stream as Stream<List<int>>;
      String buffer = '';

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);

        final lines = buffer.split('\n');
        buffer = lines.removeLast();

        for (final line in lines) {
          if (line.isEmpty || !line.startsWith('data: ')) continue;

          final data = line.substring(6).trim();
          if (data.isEmpty) continue;

          try {
            final json = jsonDecode(data) as Map<String, dynamic>;

            final candidates = json['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final content = candidates[0]['content'] as Map<String, dynamic>?;
              if (content != null) {
                final parts = content['parts'] as List?;
                if (parts != null && parts.isNotEmpty) {
                  final text = parts[0]['text'] as String?;
                  if (text != null && text.isNotEmpty) {
                    yield Ok(text);
                  }
                }
              }

              final finishReason = candidates[0]['finishReason'] as String?;
              if (finishReason != null && finishReason == 'STOP') {
                break;
              }
            }
          } catch (e) {
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
    if (exception.retryAfterSeconds != null) {
      return Duration(seconds: exception.retryAfterSeconds!);
    }
    return const Duration(seconds: 60);
  }

  @override
  Future<Result<bool, LlmProviderException>> isAvailable() async {
    try {
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
    return const Ok(null);
  }

  /// Build request payload for Gemini API
  Map<String, dynamic> _buildRequestPayload(LlmRequest request) {
    final contents = <Map<String, dynamic>>[];

    // Few-shot examples
    if (request.fewShotExamples != null && request.fewShotExamples!.isNotEmpty) {
      for (final example in request.fewShotExamples!) {
        contents.add({
          'role': 'user',
          'parts': [
            {'text': 'Translate: ${example.source}'}
          ],
        });
        contents.add({
          'role': 'model',
          'parts': [
            {'text': jsonEncode({example.source: example.target})}
          ],
        });
      }
    }

    // User message
    contents.add({
      'role': 'user',
      'parts': [
        {'text': _buildUserMessage(request)}
      ],
    });

    final maxTokens = request.maxTokens ?? 8192;

    final payload = <String, dynamic>{
      'contents': contents,
      'systemInstruction': {
        'parts': [
          {'text': _buildSystemPrompt(request)}
        ],
      },
      'generationConfig': {
        'temperature': request.temperature,
        'maxOutputTokens': maxTokens,
        'responseMimeType': 'application/json',
      },
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
    String modelName,
    DateTime startTime,
  ) {
    try {
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        throw const FormatException('No candidates in response');
      }

      final candidate = candidates[0] as Map<String, dynamic>;
      final finishReason = candidate['finishReason'] as String?;

      // Check for safety filtering
      if (finishReason == 'SAFETY') {
        final sourceTexts = request.texts.values.toList();
        throw LlmContentFilteredException(
          'Content blocked by safety filters. The source text may contain '
          'content that violates the provider\'s usage policies.',
          providerCode: providerCode,
          filteredTexts: sourceTexts,
          finishReason: finishReason,
        );
      }

      final content = candidate['content'] as Map<String, dynamic>?;
      if (content == null) {
        throw const FormatException('No content in candidate');
      }

      final parts = content['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        throw const FormatException('No parts in content');
      }

      final text = parts[0]['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        throw const FormatException('Empty text in response');
      }

      final translations = _parseTranslations(text, request);

      // Extract token usage
      final usageMetadata = data['usageMetadata'] as Map<String, dynamic>? ?? {};
      final inputTokens = usageMetadata['promptTokenCount'] as int? ?? 0;
      final outputTokens = usageMetadata['candidatesTokenCount'] as int? ?? 0;

      final processingTime = DateTime.now().difference(startTime).inMilliseconds;

      return LlmResponse(
        requestId: request.requestId,
        translations: translations,
        providerCode: providerCode,
        modelName: modelName,
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

      final markdownMatch = RegExp(
        r'```(?:json)?\s*(\{[\s\S]*?\})\s*```',
        multiLine: true,
      ).firstMatch(jsonText);

      if (markdownMatch != null) {
        jsonText = markdownMatch.group(1)!;
      }

      final dynamic parsed = jsonDecode(jsonText);

      if (parsed is! Map) {
        throw const FormatException('Response is not a JSON object');
      }

      final Map<String, String> translations = {};

      if (parsed.containsKey('translations')) {
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
        parsed.forEach((key, value) {
          translations[key.toString()] = value.toString();
        });
      }

      final emptyKeys = translations.entries
          .where((e) => e.value.trim().isEmpty)
          .map((e) => e.key)
          .toList();

      for (final key in emptyKeys) {
        translations.remove(key);
      }

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

    String errorMessage = 'Unknown error';
    String? errorStatus;

    if (responseData is Map<String, dynamic>) {
      final error = responseData['error'] as Map<String, dynamic>?;
      if (error != null) {
        errorMessage = error['message'] as String? ?? errorMessage;
        errorStatus = error['status'] as String?;
      }
    } else if (responseData != null) {
      errorMessage = responseData.toString();
    }

    if (statusCode == 401 || statusCode == 403) {
      return LlmAuthenticationException(
        'Invalid API key: $errorMessage',
        providerCode: providerCode,
      );
    }

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

    if (statusCode == 400 && errorStatus == 'INVALID_ARGUMENT') {
      if (errorMessage.toLowerCase().contains('token')) {
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

    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      return LlmInvalidRequestException(
        errorMessage,
        providerCode: providerCode,
      );
    }

    if (statusCode != null && statusCode >= 500) {
      return LlmServerException(
        'Server error: $errorMessage',
        providerCode: providerCode,
        statusCode: statusCode,
      );
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return LlmNetworkException(
        'Request timeout: ${e.message}',
        providerCode: providerCode,
      );
    }

    if (e.type == DioExceptionType.connectionError) {
      return LlmNetworkException(
        'Connection failed: ${e.message}',
        providerCode: providerCode,
      );
    }

    return LlmNetworkException(
      'Network error: ${e.message ?? errorMessage}',
      providerCode: providerCode,
    );
  }
}
