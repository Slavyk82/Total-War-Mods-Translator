import 'dart:convert';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';

/// Result containing the formatted prompt preview
class PromptPreview {
  /// The system message (instructions, context, glossary)
  final String systemMessage;

  /// The user message (the actual translation request)
  final String userMessage;

  /// Full prompt as it would be sent to the LLM
  final String fullPrompt;

  /// Provider-specific formatted payload (JSON)
  final String formattedPayload;

  /// Estimated token count
  final int estimatedTokens;

  /// Provider code
  final String providerCode;

  /// Model name
  final String modelName;

  const PromptPreview({
    required this.systemMessage,
    required this.userMessage,
    required this.fullPrompt,
    required this.formattedPayload,
    required this.estimatedTokens,
    required this.providerCode,
    required this.modelName,
  });
}

/// Service for generating prompt previews for translation units
///
/// Allows users to see exactly what will be sent to the LLM
/// before starting a translation batch.
class PromptPreviewService {
  final IPromptBuilderService _promptBuilder;

  PromptPreviewService(this._promptBuilder);

  /// Build a preview of the prompt that would be sent for a single unit
  ///
  /// [unit]: The translation unit to preview
  /// [context]: The translation context with settings
  ///
  /// Returns a [PromptPreview] with the full formatted prompt
  Future<Result<PromptPreview, String>> buildPreview({
    required TranslationUnit unit,
    required TranslationContext context,
  }) async {
    try {
      // Build the prompt using the same service as actual translation
      final result = await _promptBuilder.buildPrompt(
        units: [unit],
        context: context,
        includeExamples: true,
        maxExamples: 3,
      );

      if (result.isErr) {
        return Err('Failed to build prompt: ${result.unwrapErr()}');
      }

      final builtPrompt = result.unwrap();
      final providerCode = context.providerCode ?? AppConstants.defaultLlmProvider;
      final modelName = context.modelId ?? 'default';

      // Format as the actual API payload that would be sent
      final formattedPayload = _formatAsApiPayload(
        systemMessage: builtPrompt.systemMessage,
        userMessage: builtPrompt.userMessage,
        unitId: unit.id,
        sourceText: unit.sourceText,
        targetLanguage: context.targetLanguage,
        providerCode: providerCode,
        modelName: modelName,
      );

      // Estimate tokens (rough estimate: ~4 chars per token)
      final fullPrompt = '${builtPrompt.systemMessage}\n\n${builtPrompt.userMessage}';
      final estimatedTokens = (fullPrompt.length / 4).ceil();

      return Ok(PromptPreview(
        systemMessage: builtPrompt.systemMessage,
        userMessage: builtPrompt.userMessage,
        fullPrompt: fullPrompt,
        formattedPayload: formattedPayload,
        estimatedTokens: estimatedTokens,
        providerCode: providerCode,
        modelName: modelName,
      ));
    } catch (e) {
      return Err('Error building prompt preview: $e');
    }
  }

  /// Format the prompt as it would appear in the actual API request
  String _formatAsApiPayload({
    required String systemMessage,
    required String userMessage,
    required String unitId,
    required String sourceText,
    required String targetLanguage,
    required String providerCode,
    required String modelName,
  }) {
    // Format depends on provider
    if (providerCode == 'anthropic') {
      return _formatAnthropicPayload(
        systemMessage: systemMessage,
        userMessage: userMessage,
        modelName: modelName,
      );
    } else {
      // Default to OpenAI-style format (also used by OpenRouter)
      return _formatOpenAiPayload(
        systemMessage: systemMessage,
        userMessage: userMessage,
        modelName: modelName,
      );
    }
  }

  String _formatOpenAiPayload({
    required String systemMessage,
    required String userMessage,
    required String modelName,
  }) {
    final payload = {
      'model': modelName,
      'messages': [
        {
          'role': 'system',
          'content': systemMessage,
        },
        {
          'role': 'user',
          'content': userMessage,
        },
      ],
      'temperature': 0.3,
      'response_format': {'type': 'json_object'},
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  String _formatAnthropicPayload({
    required String systemMessage,
    required String userMessage,
    required String modelName,
  }) {
    final payload = {
      'model': modelName,
      'max_tokens': 4096,
      'temperature': 0.3,
      'system': systemMessage,
      'messages': [
        {
          'role': 'user',
          'content': userMessage,
        },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(payload);
  }
}

