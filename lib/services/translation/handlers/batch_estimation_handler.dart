import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/translation_batch_repository.dart';
import 'package:twmt/repositories/translation_batch_unit_repository.dart';
import 'package:twmt/repositories/translation_provider_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/service_locator.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/i_prompt_builder_service.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/services/translation/models/batch_estimate.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';

/// Handles batch estimation, validation, and statistics calculations
///
/// Responsibilities:
/// - Estimate tokens and duration for batch translation
/// - Validate batch configuration before translation
/// - Calculate batch statistics from database
class BatchEstimationHandler {
  final ILlmService _llmService;
  final IPromptBuilderService _promptBuilder;
  final TranslationBatchRepository _batchRepository;
  final TranslationBatchUnitRepository _batchUnitRepository;
  final TranslationUnitRepository _unitRepository;
  final TranslationVersionRepository _versionRepository;
  final LoggingService _logger;

  BatchEstimationHandler({
    required ILlmService llmService,
    required IPromptBuilderService promptBuilder,
    required TranslationBatchRepository batchRepository,
    required TranslationBatchUnitRepository batchUnitRepository,
    required TranslationUnitRepository unitRepository,
    required TranslationVersionRepository versionRepository,
    required LoggingService logger,
  })  : _llmService = llmService,
        _promptBuilder = promptBuilder,
        _batchRepository = batchRepository,
        _batchUnitRepository = batchUnitRepository,
        _unitRepository = unitRepository,
        _versionRepository = versionRepository,
        _logger = logger;

  /// Estimate tokens, TM reuse, and duration for a batch
  ///
  /// [batchId]: The batch to estimate
  /// [units]: Translation units in the batch
  /// [context]: Translation context
  Future<Result<BatchEstimate, TranslationOrchestrationException>> estimateBatch({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
  }) async {
    try {
      _logger.info('Estimating batch', {'batchId': batchId});

      if (units.isEmpty) {
        return Err(EmptyBatchException('Batch has no units', batchId: batchId));
      }

      // Check TM for exact/fuzzy matches using batch query (optimized)
      final unitIds = units.map((u) => u.id).toList();
      final translatedIdsResult = await _versionRepository.getTranslatedUnitIds(
        unitIds: unitIds,
        projectLanguageId: context.projectLanguageId,
      );

      final tmMatchCount = translatedIdsResult.isOk
          ? translatedIdsResult.unwrap().length
          : 0;

      final unitsRequiringLlm = units.length - tmMatchCount;
      final tmReuseRate = units.isNotEmpty ? tmMatchCount / units.length : 0.0;

      // Build prompt for token estimation
      final promptResult = await _promptBuilder.buildPrompt(
        units: units.take(unitsRequiringLlm).toList(),
        context: context,
        includeExamples: true,
        maxExamples: 3,
      );

      if (promptResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to build prompt for estimation: ${promptResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      // Create LLM request for token estimation
      final textsMap = <String, String>{};
      for (var i = 0; i < unitsRequiringLlm && i < units.length; i++) {
        textsMap[units[i].id] = units[i].sourceText;
      }

      final llmRequest = LlmRequest(
        requestId: 'estimate-$batchId',
        texts: textsMap,
        targetLanguage: context.targetLanguage,
        systemPrompt: promptResult.unwrap().systemMessage,
        modelName: context.modelId,
        providerCode: context.providerCode,
        gameContext: context.gameContext,
        glossaryTerms: context.glossaryTerms,
        timestamp: DateTime.now(),
      );

      // Estimate tokens using LLM service
      final tokensResult = await _llmService.estimateTokens(llmRequest);
      if (tokensResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to estimate tokens: ${tokensResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      final estimatedTokens = tokensResult.unwrap();
      // Split tokens: ~40% input (source text), ~60% output (translation)
      final estimatedInputTokens = (estimatedTokens * 0.4).round();
      final estimatedOutputTokens = (estimatedTokens * 0.6).round();

      // Get provider info
      final providerCode = await _llmService.getActiveProviderCode();

      // Get model name from provider configuration
      String modelName = 'Unknown';
      try {
        final providerRepo = ServiceLocator.get<TranslationProviderRepository>();
        final providerResult = await providerRepo.getByCode(providerCode);

        if (providerResult.isOk) {
          final provider = providerResult.unwrap();
          modelName = provider.defaultModel ?? 'Unknown';
        }
      } catch (e) {
        _logger.warning('Failed to get provider model name: $e');
      }

      // Estimate duration (rough: 50 units per minute)
      final estimatedDurationSeconds =
          ((unitsRequiringLlm / AppConstants.estimatedUnitsPerMinute) * 60).round();

      final estimate = BatchEstimate(
        batchId: batchId,
        totalUnits: units.length,
        estimatedInputTokens: estimatedInputTokens,
        estimatedOutputTokens: estimatedOutputTokens,
        totalEstimatedTokens: estimatedTokens,
        providerCode: providerCode,
        modelName: modelName,
        unitsFromTm: tmMatchCount,
        unitsRequiringLlm: unitsRequiringLlm,
        tmReuseRate: tmReuseRate,
        estimatedDurationSeconds: estimatedDurationSeconds,
        createdAt: DateTime.now(),
      );

      _logger.info('Batch estimation completed', {
        'batchId': batchId,
        'totalUnits': units.length,
        'unitsFromTm': tmMatchCount,
        'unitsRequiringLlm': unitsRequiringLlm,
        'estimatedTokens': estimatedTokens,
      });

      return Ok(estimate);
    } catch (e, stackTrace) {
      _logger.error('Batch estimation failed', e, stackTrace);
      return Err(
        TranslationOrchestrationException(
          'Failed to estimate batch: ${e.toString()}',
          batchId: batchId,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Validate batch configuration before translation
  ///
  /// Returns list of validation errors, or empty list if valid.
  Future<List<ValidationError>> validateBatch({
    required String batchId,
    required TranslationContext context,
  }) async {
    final errors = <ValidationError>[];

    // Validate batch ID
    if (batchId.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Batch ID cannot be empty',
        field: 'batchId',
      ));
    }

    // Validate context
    if (context.projectId.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Project ID cannot be empty',
        field: 'projectId',
      ));
    }

    if (context.targetLanguage.trim().isEmpty) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Target language cannot be empty',
        field: 'targetLanguage',
      ));
    }

    // Check if batch exists in database
    final batchResult = await _batchRepository.getById(batchId);
    if (batchResult.isErr) {
      errors.add(ValidationError(
        severity: ValidationSeverity.error,
        message: 'Batch does not exist in database',
        field: 'batchId',
      ));
    }

    return errors;
  }

  /// Get aggregated statistics for completed batches
  ///
  /// [batchIds]: List of batch IDs to include, or null for all batches
  /// [since]: Only include batches completed after this timestamp
  Future<BatchStatistics> getBatchStatistics({
    List<String>? batchIds,
    DateTime? since,
  }) async {
    try {
      // Build query conditions
      final conditions = <String>[];
      final args = <dynamic>[];

      if (batchIds != null && batchIds.isNotEmpty) {
        final placeholders = List.filled(batchIds.length, '?').join(', ');
        conditions.add('tb.id IN ($placeholders)');
        args.addAll(batchIds);
      }

      if (since != null) {
        conditions.add('tb.started_at >= ?');
        args.add(since.millisecondsSinceEpoch ~/ 1000);
      }

      // Only include completed or failed batches for accurate statistics
      conditions.add("tb.status IN ('completed', 'failed')");

      final whereClause =
          conditions.isNotEmpty ? 'WHERE ${conditions.join(' AND ')}' : '';

      // Query batch statistics from database
      final db = _batchRepository.database;
      final result = await db.rawQuery('''
        SELECT
          COUNT(DISTINCT tb.id) as total_batches,
          COALESCE(SUM(tb.units_count), 0) as total_units,
          COALESCE(SUM(tb.units_completed), 0) as total_completed,
          COALESCE(SUM(CASE WHEN tb.status = 'completed' THEN tb.units_completed ELSE 0 END), 0) as total_successful,
          COALESCE(SUM(CASE WHEN tb.status = 'failed' THEN tb.units_count - tb.units_completed ELSE 0 END), 0) as total_failed,
          COALESCE(AVG(CASE WHEN tb.completed_at IS NOT NULL AND tb.started_at IS NOT NULL
                       THEN (tb.completed_at - tb.started_at) * 1.0 / NULLIF(tb.units_count, 0)
                       ELSE NULL END), 0.0) as avg_time_per_unit
        FROM translation_batches tb
        $whereClause
      ''', args);

      final row = result.first;
      final totalBatches = row['total_batches'] as int;
      final totalUnits = row['total_units'] as int;
      final totalCompleted = row['total_completed'] as int;
      final totalSuccessful = row['total_successful'] as int;
      final totalFailed = row['total_failed'] as int;
      final avgTimePerUnit = (row['avg_time_per_unit'] as num).toDouble();

      // Calculate skipped units (units not requiring LLM translation due to TM matches)
      final totalSkipped = totalUnits - totalCompleted;

      return BatchStatistics(
        totalBatches: totalBatches,
        totalUnitsProcessed: totalCompleted,
        totalSuccessful: totalSuccessful,
        totalFailed: totalFailed,
        totalSkipped: totalSkipped > 0 ? totalSkipped : 0,
        totalTokensUsed: 0,
        averageTmReuseRate: 0.0,
        averageTimePerUnit: avgTimePerUnit,
      );
    } catch (e, stackTrace) {
      _logger.error('Failed to get batch statistics', e, stackTrace);

      // Return empty statistics on error
      return const BatchStatistics(
        totalBatches: 0,
        totalUnitsProcessed: 0,
        totalSuccessful: 0,
        totalFailed: 0,
        totalSkipped: 0,
        totalTokensUsed: 0,
        averageTmReuseRate: 0.0,
        averageTimePerUnit: 0.0,
      );
    }
  }

  /// Load translation units for a batch from database
  ///
  /// Performance optimized: Uses batch query instead of N individual queries.
  Future<Result<List<TranslationUnit>, TranslationOrchestrationException>>
      loadBatchUnits(String batchId) async {
    try {
      // Get batch-unit associations (1 query)
      final batchUnitsResult = await _batchUnitRepository.findByBatchId(batchId);
      if (batchUnitsResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to load batch units: ${batchUnitsResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      final batchUnits = batchUnitsResult.unwrap();
      final unitIds = batchUnits.map((bu) => bu.unitId).toList();

      // Load actual translation units in one batch query (1 query instead of N)
      final unitsResult = await _unitRepository.getByIds(unitIds);
      if (unitsResult.isErr) {
        return Err(TranslationOrchestrationException(
          'Failed to load translation units: ${unitsResult.unwrapErr()}',
          batchId: batchId,
        ));
      }

      return Ok(unitsResult.unwrap());
    } catch (e, stackTrace) {
      _logger.error('Failed to load batch units', e, stackTrace);
      return Err(TranslationOrchestrationException(
        'Failed to load batch units: ${e.toString()}',
        batchId: batchId,
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }
}
