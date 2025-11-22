import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// Service responsible for batch size validation and adjustment
///
/// This service handles the complex logic of validating translation batch sizes
/// against provider token limits and splitting oversized batches into smaller
/// chunks that fit within constraints.
///
/// Responsibilities:
/// - Validate batch sizes against provider limits
/// - Calculate token overhead (system prompt, context, glossary)
/// - Split large batches into smaller ones
/// - Optimize batch sizes for performance and efficiency
class LlmBatchAdjuster {
  final LlmProviderFactory _providerFactory;
  final TokenCalculator _tokenCalculator;

  LlmBatchAdjuster({
    required LlmProviderFactory providerFactory,
    required TokenCalculator tokenCalculator,
  })  : _providerFactory = providerFactory,
        _tokenCalculator = tokenCalculator;

  /// Validate if a batch fits within provider token limits
  ///
  /// Returns Ok(true) if batch is valid, Ok(false) if it needs splitting.
  /// Returns Err if validation fails.
  Future<Result<bool, LlmServiceException>> validateBatchSize(
    LlmRequest request,
    String providerCode,
  ) async {
    try {
      // Get provider configuration
      final provider = _providerFactory.getProvider(providerCode);
      final config = provider.config;

      // Estimate total tokens for this request
      final estimatedTokens = provider.estimateRequestTokens(request);

      // Check against provider's token limit
      if (estimatedTokens > config.maxTokensPerRequest) {
        return Ok(false);
      }

      return Ok(true);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to validate batch size: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Adjust batch size by splitting into smaller batches if needed
  ///
  /// If the batch fits within limits, returns it as-is.
  /// If it exceeds limits, splits it into multiple smaller batches.
  Future<Result<List<LlmRequest>, LlmServiceException>> adjustBatchSize(
    LlmRequest request,
    String providerCode,
  ) async {
    try {
      // First validate if batch needs splitting
      final validationResult = await validateBatchSize(request, providerCode);
      if (validationResult.isErr) {
        return Err(validationResult.error);
      }

      // If batch size is valid, return as-is
      if (validationResult.value) {
        return Ok([request]);
      }

      // Get provider configuration for token limits
      final provider = _providerFactory.getProvider(providerCode);
      final config = provider.config;

      // Calculate overhead tokens (system prompt, context, examples)
      final overheadTokens = calculateOverheadTokens(request);

      // Calculate available tokens for texts with safety margin
      final availableTokensForTexts =
          (config.maxTokensPerRequest * AppConstants.tokenSafetyMargin).floor() -
              overheadTokens;

      if (availableTokensForTexts <= 0) {
        return Err(
          LlmValidationException(
            'Request overhead (system prompt, context) exceeds token limit',
            details: {
              'overheadTokens': overheadTokens,
              'maxTokens': config.maxTokensPerRequest,
              'safetyMargin': AppConstants.tokenSafetyMargin,
            },
          ),
        );
      }

      // Split texts into smaller batches
      final splitRequests = splitRequestByTokens(
        request,
        availableTokensForTexts,
      );

      if (splitRequests.isEmpty) {
        return Err(
          LlmValidationException(
            'Unable to split request into valid batches',
            details: {
              'originalTexts': request.texts.length,
              'availableTokens': availableTokensForTexts,
            },
          ),
        );
      }

      return Ok(splitRequests);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to adjust batch size: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Calculate overhead tokens for a request
  ///
  /// Overhead includes:
  /// - System prompt
  /// - Game context
  /// - Project context
  /// - Few-shot examples
  /// - Glossary terms
  /// - JSON structure overhead
  int calculateOverheadTokens(LlmRequest request) {
    int overhead = 0;

    // System prompt
    overhead += _tokenCalculator.calculateTokens(request.systemPrompt);

    // Game context
    if (request.gameContext != null) {
      overhead += _tokenCalculator.calculateTokens(request.gameContext!);
    }

    // Project context
    if (request.projectContext != null) {
      overhead += _tokenCalculator.calculateTokens(request.projectContext!);
    }

    // Few-shot examples
    if (request.fewShotExamples != null) {
      for (final example in request.fewShotExamples!) {
        overhead += _tokenCalculator.calculateTokens(example.source);
        overhead += _tokenCalculator.calculateTokens(example.target);
      }
    }

    // Glossary terms
    if (request.glossaryTerms != null) {
      overhead += _tokenCalculator.calculateTokensForMap(request.glossaryTerms!);
    }

    // Add JSON structure overhead
    overhead = (overhead * AppConstants.jsonOverheadMultiplier).ceil();

    return overhead;
  }

  /// Split request into smaller batches based on token limits
  ///
  /// Groups text entries into batches that fit within the specified token limit.
  /// Skips entries that are too large to fit in any batch.
  List<LlmRequest> splitRequestByTokens(
    LlmRequest request,
    int maxTokensForTexts,
  ) {
    final batches = <LlmRequest>[];
    final textEntries = request.texts.entries.toList();

    var currentBatch = <String, String>{};
    var currentTokens = 0;

    for (final entry in textEntries) {
      // Calculate tokens for this text entry
      final entryTokens = calculateTextEntryTokens(entry.key, entry.value);

      // If single entry exceeds limit, skip it
      // TODO: Consider logging warning about oversized entries
      if (entryTokens > maxTokensForTexts) {
        continue;
      }

      // If adding this entry would exceed limit, create new batch
      if (currentTokens + entryTokens > maxTokensForTexts &&
          currentBatch.isNotEmpty) {
        batches.add(createBatchRequest(request, currentBatch, batches.length));
        currentBatch = {};
        currentTokens = 0;
      }

      // Add entry to current batch
      currentBatch[entry.key] = entry.value;
      currentTokens += entryTokens;
    }

    // Add final batch if not empty
    if (currentBatch.isNotEmpty) {
      batches.add(createBatchRequest(request, currentBatch, batches.length));
    }

    return batches;
  }

  /// Calculate tokens for a single text entry
  ///
  /// Includes:
  /// - Key tokens
  /// - Value (input) tokens
  /// - Estimated output tokens
  int calculateTextEntryTokens(String key, String value) {
    final keyTokens = _tokenCalculator.calculateTokens(key);
    final valueTokens = _tokenCalculator.calculateTokens(value);
    final outputEstimate = (valueTokens * AppConstants.outputEstimateMultiplier).ceil();

    return keyTokens + valueTokens + outputEstimate;
  }

  /// Create a batch request with subset of texts
  ///
  /// Creates a new request with the same configuration but only
  /// the specified text entries. Updates request ID and timestamp.
  LlmRequest createBatchRequest(
    LlmRequest originalRequest,
    Map<String, String> texts,
    int batchIndex,
  ) {
    return originalRequest.copyWith(
      requestId: '${originalRequest.requestId}_batch_$batchIndex',
      texts: texts,
      timestamp: DateTime.now(),
    );
  }

  /// Estimate total tokens for a request (including overhead)
  ///
  /// This is a convenience method that calculates both overhead
  /// and text tokens to get the total token count.
  int estimateTotalTokens(LlmRequest request) {
    final overhead = calculateOverheadTokens(request);

    var textTokens = 0;
    for (final entry in request.texts.entries) {
      textTokens += calculateTextEntryTokens(entry.key, entry.value);
    }

    return overhead + textTokens;
  }
}
