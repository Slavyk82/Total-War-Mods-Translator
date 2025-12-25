import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/llm/i_llm_service.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/llm_batch_adjuster.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/models/llm_response.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';
import 'package:twmt/services/llm/utils/concurrency_semaphore.dart';
import 'package:twmt/services/glossary/deepl_glossary_sync_service.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of high-level LLM service
///
/// This service orchestrates LLM providers, handles rate limiting,
/// and provides a unified interface for translation.
///
/// Core responsibilities:
/// - Provider coordination and API key management
/// - Parallel batch translation with concurrency control
/// - Streaming translation support
/// - Token estimation
class LlmServiceImpl implements ILlmService {
  final LlmProviderFactory _providerFactory;
  final LlmBatchAdjuster _batchAdjuster;
  final SettingsService _settingsService;
  final FlutterSecureStorage _secureStorage;
  final LoggingService _logging;

  /// Lazy getter for DeepL glossary sync service.
  /// Uses a factory function to defer resolution until the service is registered.
  final DeepLGlossarySyncService? Function()? _deeplGlossarySyncServiceFactory;

  /// API key setting key pattern: "{providerCode}_api_key"
  static const String _apiKeySuffix = '_api_key';

  /// Active provider setting key
  static const String _activeProviderKey = 'active_llm_provider';

  LlmServiceImpl({
    required LlmProviderFactory providerFactory,
    required LlmBatchAdjuster batchAdjuster,
    required SettingsService settingsService,
    required FlutterSecureStorage secureStorage,
    DeepLGlossarySyncService? Function()? deeplGlossarySyncServiceFactory,
    LoggingService? logging,
  })  : _providerFactory = providerFactory,
        _batchAdjuster = batchAdjuster,
        _settingsService = settingsService,
        _secureStorage = secureStorage,
        _deeplGlossarySyncServiceFactory = deeplGlossarySyncServiceFactory,
        _logging = logging ?? LoggingService.instance;

  /// Get the DeepL glossary sync service (lazy resolution).
  DeepLGlossarySyncService? get _deeplGlossarySyncService =>
      _deeplGlossarySyncServiceFactory?.call();

  @override
  Future<Result<LlmResponse, LlmServiceException>> translateBatch(
    LlmRequest request, {
    CancelToken? cancelToken,
  }) async {
    try {
      // Use provider from request if specified, otherwise fall back to active provider
      final providerCode = request.providerCode ?? await getActiveProviderCode();
      final apiKey = await _getApiKey(providerCode);

      if (apiKey.isEmpty) {
        return Err(
          LlmAuthenticationException(
            'API key not configured for provider: $providerCode',
            providerCode: providerCode,
            code: 'MISSING_API_KEY',
            details: {
              'providerCode': providerCode,
              'message': 'Please configure an API key in settings',
            },
          ),
        );
      }

      // Get provider instance
      final provider = _providerFactory.getProvider(providerCode);

      // Special handling for DeepL with glossary
      if (providerCode == 'deepl' &&
          provider is DeepLProvider &&
          request.glossaryId != null &&
          request.sourceLanguage != null &&
          _deeplGlossarySyncService != null) {
        return _translateWithDeepLGlossary(
          request: request,
          provider: provider,
          apiKey: apiKey,
          cancelToken: cancelToken,
        );
      }

      // Standard translation
      final result = await provider.translate(request, apiKey, cancelToken: cancelToken);

      return result.when(
        ok: (response) => Ok(response),
        err: (error) => Err(error),
      );
    } on LlmServiceException catch (e) {
      // Already an LlmServiceException, return as-is
      return Err(e);
    } catch (e, stackTrace) {
      // Wrap unexpected errors
      return Err(
        LlmServiceException(
          'Failed to translate batch: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Translate using DeepL with glossary sync.
  ///
  /// Syncs the glossary to DeepL servers if needed, then uses
  /// the DeepL glossary ID for translation.
  Future<Result<LlmResponse, LlmServiceException>> _translateWithDeepLGlossary({
    required LlmRequest request,
    required DeepLProvider provider,
    required String apiKey,
    CancelToken? cancelToken,
  }) async {
    try {
      _logging.debug('[LlmServiceImpl] Syncing glossary for DeepL translation', {
        'glossaryId': request.glossaryId,
        'sourceLanguage': request.sourceLanguage,
        'targetLanguage': request.targetLanguage,
      });

      // Sync glossary to DeepL
      final syncResult = await _deeplGlossarySyncService!.ensureGlossarySynced(
        glossaryId: request.glossaryId!,
        sourceLanguageCode: request.sourceLanguage!,
        targetLanguageCode: request.targetLanguage,
      );

      if (syncResult.isErr) {
        _logging.warning('[LlmServiceImpl] Glossary sync failed, using standard translation', {
          'error': syncResult.error.message,
        });
        // Fall back to standard translation without glossary
        final result = await provider.translate(request, apiKey, cancelToken: cancelToken);
        return result.when(
          ok: (response) => Ok(response),
          err: (error) => Err(error),
        );
      }

      final deeplGlossaryId = syncResult.value;

      if (deeplGlossaryId == null) {
        _logging.debug('[LlmServiceImpl] No glossary entries for language pair, using standard translation');
        // No glossary entries for this language pair, use standard translation
        final result = await provider.translate(request, apiKey, cancelToken: cancelToken);
        return result.when(
          ok: (response) => Ok(response),
          err: (error) => Err(error),
        );
      }

      _logging.info('[LlmServiceImpl] Using DeepL glossary for translation', {
        'deeplGlossaryId': deeplGlossaryId,
      });

      // Translate with glossary
      final result = await provider.translateWithGlossary(
        request: request,
        apiKey: apiKey,
        glossaryId: deeplGlossaryId,
      );

      return result.when(
        ok: (response) => Ok(response),
        err: (error) => Err(error),
      );
    } catch (e, stackTrace) {
      _logging.error('[LlmServiceImpl] Error during DeepL glossary translation', e, stackTrace);
      return Err(
        LlmServiceException(
          'Failed to translate with DeepL glossary: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Stream<Result<BatchTranslationResult, LlmServiceException>>
      translateBatchesParallel(
    List<LlmRequest> requests, {
    int maxParallel = AppConstants.maxParallelBatches,
  }) async* {
    // Validate maxParallel parameter
    final concurrency = maxParallel.clamp(1, AppConstants.maxConcurrentLlmRequests);

    // Create stream controller for results
    final controller = StreamController<Result<BatchTranslationResult, LlmServiceException>>();
    final semaphore = ConcurrencySemaphore(maxConcurrent: concurrency);

    // Track active futures for cleanup
    final activeFutures = <Future<void>>[];
    var isProcessingComplete = false;

    // Process all requests with controlled concurrency
    Future<void> processRequests() async {
      try {
        for (var i = 0; i < requests.length; i++) {
          final request = requests[i];

          // Wait for semaphore slot
          final future = semaphore.acquire().then((_) async {
            try {
              final startTime = DateTime.now();
              final result = await translateBatch(request);
              final endTime = DateTime.now();

              // Only add to controller if not yet closed
              if (!controller.isClosed) {
                // Use pattern matching for safer Result handling
                result.when(
                  ok: (response) {
                    controller.add(Ok(BatchTranslationResult(
                      batchId: request.requestId,
                      totalUnits: response.translations.length,
                      successfulUnits: response.translations.length,
                      failedUnits: 0,
                      responses: [response],
                      errors: {},
                      totalTokens: response.totalTokens,
                      totalProcessingTimeMs: response.processingTimeMs,
                      startTime: startTime,
                      endTime: endTime,
                    )));
                  },
                  err: (error) {
                    controller.add(Ok(BatchTranslationResult(
                      batchId: request.requestId,
                      totalUnits: request.texts.length,
                      successfulUnits: 0,
                      failedUnits: request.texts.length,
                      responses: [],
                      errors: {request.requestId: error.message},
                      totalTokens: 0,
                      totalProcessingTimeMs: endTime.difference(startTime).inMilliseconds,
                      startTime: startTime,
                      endTime: endTime,
                    )));
                  },
                );
              }
            } catch (e, stackTrace) {
              // Handle unexpected errors during batch processing
              if (!controller.isClosed) {
                controller.add(Err(
                  LlmServiceException(
                    'Unexpected error during batch translation: ${e.toString()}',
                    stackTrace: stackTrace,
                  ),
                ));
              }
            } finally {
              // Always release semaphore slot
              semaphore.release();
            }
          });

          activeFutures.add(future);
        }

        // Wait for all requests to complete
        await Future.wait(activeFutures, eagerError: false);
      } catch (e, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(e, stackTrace);
        }
      } finally {
        isProcessingComplete = true;
        // Close controller after all processing is done
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }

    // Start processing in background
    // ignore: unawaited_futures
    processRequests();

    // Yield results as they become available
    try {
      yield* controller.stream;
    } finally {
      // Ensure cleanup if stream is cancelled before processing completes
      if (!isProcessingComplete && !controller.isClosed) {
        await controller.close();
      }
    }
  }

  @override
  Future<Result<int, LlmServiceException>> estimateTokens(
    LlmRequest request,
  ) async {
    try {
      // Use batch adjuster for token estimation
      final estimatedTokens = _batchAdjuster.estimateTotalTokens(request);

      return Ok(estimatedTokens);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to estimate tokens: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<bool, LlmServiceException>> validateBatchSize(
    LlmRequest request,
  ) async {
    try {
      // Delegate to batch adjuster
      final providerCode = await getActiveProviderCode();
      return await _batchAdjuster.validateBatchSize(request, providerCode);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to validate batch size: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<List<LlmRequest>, LlmServiceException>> adjustBatchSize(
    LlmRequest request,
  ) async {
    try {
      // Delegate to batch adjuster
      final providerCode = await getActiveProviderCode();
      return await _batchAdjuster.adjustBatchSize(request, providerCode);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to adjust batch size: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<bool, LlmServiceException>> validateApiKey(
    String providerCode,
    String apiKey, {
    String? model,
  }) async {
    try {
      if (apiKey.isEmpty) {
        return Err(
          LlmAuthenticationException(
            'API key cannot be empty',
            providerCode: providerCode,
            code: 'EMPTY_API_KEY',
          ),
        );
      }

      // Get provider instance
      final provider = _providerFactory.getProvider(providerCode);

      // Delegate to provider-specific validation
      final result = await provider.validateApiKey(apiKey, model: model);

      return result.when(
        ok: (_) => Ok(true),
        err: (error) => Err(error),
      );
    } on LlmConfigurationException catch (e) {
      return Err(e);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to validate API key: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<String> getActiveProviderCode() async {
    try {
      final providerCode = await _settingsService.getString(
        _activeProviderKey,
        defaultValue: AppConstants.defaultLlmProvider,
      );
      return providerCode.isEmpty ? AppConstants.defaultLlmProvider : providerCode;
    } catch (e) {
      // If settings service fails, return default
      return AppConstants.defaultLlmProvider;
    }
  }

  @override
  Future<Result<void, LlmServiceException>> setActiveProvider(
    String providerCode,
  ) async {
    try {
      // Validate provider code exists
      if (!getAvailableProviders().contains(providerCode)) {
        return Err(
          LlmConfigurationException(
            'Invalid provider code: $providerCode',
            code: 'INVALID_PROVIDER',
            details: {
              'providerCode': providerCode,
              'availableProviders': getAvailableProviders(),
            },
          ),
        );
      }

      // Save to settings
      final result = await _settingsService.setString(
        _activeProviderKey,
        providerCode,
      );

      return result.when(
        ok: (_) => Ok(null),
        err: (error) => Err(
          LlmServiceException(
            'Failed to save active provider: ${error.message}',
            code: 'SETTINGS_ERROR',
          ),
        ),
      );
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to set active provider: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<bool> supportsStreaming() async {
    try {
      final providerCode = await getActiveProviderCode();
      final provider = _providerFactory.getProvider(providerCode);
      return provider.supportsStreaming;
    } catch (e) {
      return false;
    }
  }

  @override
  Stream<Result<String, LlmServiceException>> translateStreaming(
    LlmRequest request,
  ) async* {
    try {
      // Get active provider and check streaming support
      final providerCode = await getActiveProviderCode();
      final provider = _providerFactory.getProvider(providerCode);

      if (!provider.supportsStreaming) {
        yield Err(
          LlmUnsupportedOperationException(
            'Provider $providerCode does not support streaming',
            operation: 'translateStreaming',
            details: {
              'providerCode': providerCode,
              'supportsStreaming': false,
            },
          ),
        );
        return;
      }

      // Get API key
      final apiKey = await _getApiKey(providerCode);
      if (apiKey.isEmpty) {
        yield Err(
          LlmAuthenticationException(
            'API key not configured for provider: $providerCode',
            providerCode: providerCode,
            code: 'MISSING_API_KEY',
          ),
        );
        return;
      }

      // Stream translation directly
      await for (final result in provider.translateStreaming(request, apiKey)) {
        if (result.isErr) {
          yield Err(result.error);
        } else {
          yield Ok(result.value);
        }
      }
    } catch (e, stackTrace) {
      yield Err(
        LlmServiceException(
          'Streaming translation failed: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<ProviderStatistics, LlmServiceException>> getProviderStats(
    String providerCode, {
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    try {
      // Get provider ID from database
      final db = DatabaseService.database;
      final providerResult = await db.query(
        'translation_providers',
        where: 'code = ?',
        whereArgs: [providerCode],
        limit: 1,
      );

      if (providerResult.isEmpty) {
        return Err(
          LlmConfigurationException(
            'Provider not found: $providerCode',
            code: 'PROVIDER_NOT_FOUND',
          ),
        );
      }

      final providerId = providerResult.first['id'] as String;

      // Build time range conditions
      final conditions = <String>['tb.provider_id = ?'];
      final args = <dynamic>[providerId];

      if (fromDate != null) {
        conditions.add('tb.started_at >= ?');
        args.add(fromDate.millisecondsSinceEpoch ~/ 1000);
      }

      if (toDate != null) {
        conditions.add('tb.started_at <= ?');
        args.add(toDate.millisecondsSinceEpoch ~/ 1000);
      }

      final whereClause = 'WHERE ${conditions.join(' AND ')}';

      // Query statistics from translation_batches table
      final result = await db.rawQuery('''
        SELECT
          COUNT(*) as total_requests,
          SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END) as successful_requests,
          SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_requests,
          AVG(CASE
            WHEN completed_at IS NOT NULL AND started_at IS NOT NULL
            THEN (completed_at - started_at) * 1000.0
            ELSE NULL
          END) as avg_response_time_ms
        FROM translation_batches tb
        $whereClause
      ''', args);

      final row = result.first;
      final totalRequests = row['total_requests'] as int;
      final successfulRequests = row['successful_requests'] as int;
      final failedRequests = row['failed_requests'] as int;
      final avgResponseTimeMs = (row['avg_response_time_ms'] as num?)?.toDouble() ?? 0.0;

      final stats = ProviderStatistics(
        providerCode: providerCode,
        totalRequests: totalRequests,
        successfulRequests: successfulRequests,
        failedRequests: failedRequests,
        totalInputTokens: 0,
        totalOutputTokens: 0,
        averageResponseTimeMs: avgResponseTimeMs,
        fromDate: fromDate ?? DateTime.now(),
        toDate: toDate ?? DateTime.now(),
      );

      return Ok(stats);
    } catch (e, stackTrace) {
      return Err(
        LlmServiceException(
          'Failed to get provider statistics: ${e.toString()}',
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  List<String> getAvailableProviders() {
    return _providerFactory.getAvailableProviders();
  }

  @override
  Future<Result<bool, LlmServiceException>> isProviderAvailable(
    String providerCode,
  ) async {
    try {
      // Check if provider exists in factory
      if (!_providerFactory.hasProvider(providerCode)) {
        return Ok(false);
      }

      // Get provider instance
      final provider = _providerFactory.getProvider(providerCode);

      // Delegate to provider-specific availability check
      final result = await provider.isAvailable();

      return result.when(
        ok: (available) => Ok(available),
        err: (_) => Ok(false), // Provider exists but not reachable
      );
    } catch (e) {
      return Ok(false);
    }
  }

  // ========== Private Helper Methods ==========

  /// Get API key for a provider from secure storage
  Future<String> _getApiKey(String providerCode) async {
    try {
      final settingKey = '$providerCode$_apiKeySuffix';
      final apiKey = await _secureStorage.read(key: settingKey) ?? '';

      return apiKey;
    } catch (e) {
      return '';
    }
  }
}
