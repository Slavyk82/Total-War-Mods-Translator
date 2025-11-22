import 'package:uuid/uuid.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/llm_provider_model.dart';
import '../../repositories/llm_provider_model_repository.dart';
import '../../services/llm/llm_provider_factory.dart';
import '../shared/logging_service.dart';

/// Service for managing LLM provider models.
///
/// Handles fetching models from provider APIs, storing them in the database,
/// archiving models that are no longer available, and managing model
/// enabled/disabled/default status.
class LlmModelManagementService {
  final LlmProviderModelRepository _repository;
  final LlmProviderFactory _providerFactory;
  final LoggingService _logging;
  final Uuid _uuid = const Uuid();

  LlmModelManagementService(
    this._repository,
    this._providerFactory,
    this._logging,
  );

  /// Get all models for a specific provider.
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>> getModelsByProvider(
    String providerCode,
  ) async {
    _logging.debug('[LlmModelManagement] Getting models for provider: $providerCode');
    return await _repository.getByProvider(providerCode);
  }

  /// Get all enabled models for a specific provider.
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>>
      getEnabledModelsByProvider(
    String providerCode,
  ) async {
    _logging.debug('[LlmModelManagement] Getting enabled models for provider: $providerCode');
    return await _repository.getEnabledByProvider(providerCode);
  }

  /// Get all available (non-archived) models for a specific provider.
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>>
      getAvailableModelsByProvider(
    String providerCode,
  ) async {
    _logging.debug('[LlmModelManagement] Getting available models for provider: $providerCode');
    return await _repository.getAvailableByProvider(providerCode);
  }

  /// Get the default model for a specific provider.
  Future<Result<LlmProviderModel?, TWMTDatabaseException>> getDefaultModel(
    String providerCode,
  ) async {
    _logging.debug('[LlmModelManagement] Getting default model for provider: $providerCode');
    return await _repository.getDefaultByProvider(providerCode);
  }

  /// Fetch models from provider API and store in database.
  ///
  /// This method:
  /// 1. Fetches models from the provider's API
  /// 2. Creates or updates models in the database
  /// 3. Archives models that are no longer returned by the API
  /// 4. If no default is set and models exist, sets first enabled model as default
  ///
  /// [providerCode] - Provider to fetch models for ('anthropic', 'openai', etc.)
  /// [apiKey] - API key for authentication
  ///
  /// Returns [Ok] with number of models fetched/updated, or [Err] with exception.
  Future<Result<int, ServiceException>> fetchAndStoreModels(
    String providerCode,
    String apiKey,
  ) async {
    _logging.info('[LlmModelManagement] Fetching models for provider: $providerCode');

    try {
      // Get provider instance
      final provider = _providerFactory.getProvider(providerCode);

      // Fetch models from API
      final result = await provider.fetchModels(apiKey);

      if (result.isErr) {
        final error = result.unwrapErr();
        _logging.error('[LlmModelManagement] Failed to fetch models', error);
        return Err(ServiceException(
          'Failed to fetch models from $providerCode: ${error.message}',
          error: error,
        ));
      }

      final fetchedModels = result.unwrap();
      _logging.debug('[LlmModelManagement] Fetched ${fetchedModels.length} models from API');

      if (fetchedModels.isEmpty) {
        _logging.info('[LlmModelManagement] No models returned by provider');
        return const Ok(0);
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final fetchTimestamp = now;

      // Get existing models from database
      final existingResult = await _repository.getByProvider(providerCode);
      if (existingResult.isErr) {
        final error = existingResult.unwrapErr();
        _logging.error('[LlmModelManagement] Failed to get existing models', error);
        return Err(ServiceException(
          'Failed to get existing models: ${error.message}',
          error: error,
        ));
      }

      final existingModels = existingResult.unwrap();
      final existingModelMap = <String, LlmProviderModel>{
        for (var model in existingModels) model.modelId: model
      };

      // Prepare models to upsert
      final modelsToUpsert = <LlmProviderModel>[];

      for (final fetchedModelInfo in fetchedModels) {
        final existingModel = existingModelMap[fetchedModelInfo.id];

        if (existingModel != null) {
          // Update existing model
          modelsToUpsert.add(existingModel.copyWith(
            displayName: fetchedModelInfo.displayName,
            isArchived: false, // Unarchive if it was archived
            updatedAt: now,
            lastFetchedAt: fetchTimestamp,
          ));
        } else {
          // Create new model
          modelsToUpsert.add(LlmProviderModel(
            id: _uuid.v4(),
            providerCode: providerCode,
            modelId: fetchedModelInfo.id,
            displayName: fetchedModelInfo.displayName,
            isEnabled: false, // Start disabled by default
            isDefault: false,
            isArchived: false,
            createdAt: now,
            updatedAt: now,
            lastFetchedAt: fetchTimestamp,
          ));
        }
      }

      // Upsert models
      final upsertResult = await _repository.upsertMany(modelsToUpsert);
      if (upsertResult.isErr) {
        final error = upsertResult.unwrapErr();
        _logging.error('[LlmModelManagement] Failed to upsert models', error);
        return Err(ServiceException(
          'Failed to save models: ${error.message}',
          error: error,
        ));
      }

      _logging.debug('[LlmModelManagement] Upserted ${modelsToUpsert.length} models');

      // Archive models not in the fetched list
      final archivedResult = await _repository.archiveStaleModels(
        providerCode,
        fetchTimestamp,
      );

      if (archivedResult.isErr) {
        final error = archivedResult.unwrapErr();
        _logging.error('[LlmModelManagement] Failed to archive stale models', error);
        // Don't fail the whole operation, just log the error
      } else {
        final archivedCount = archivedResult.unwrap();
        if (archivedCount > 0) {
          _logging.info('[LlmModelManagement] Archived $archivedCount stale models');
        }
      }

      // Check if a default model is set
      final defaultResult = await _repository.getDefaultByProvider(providerCode);
      if (defaultResult.isOk) {
        final defaultModel = defaultResult.unwrap();
        if (defaultModel == null) {
          // No default set, set first available model as default
          _logging.debug('[LlmModelManagement] No default model set, setting first available as default');
          if (modelsToUpsert.isNotEmpty) {
            final firstModel = modelsToUpsert.first;
            final setDefaultResult = await _repository.setAsDefault(firstModel.id);
            if (setDefaultResult.isErr) {
              _logging.error(
                '[LlmModelManagement] Failed to set default model',
                setDefaultResult.unwrapErr(),
              );
            } else {
              // Also enable the default model
              await _repository.enable(firstModel.id);
            }
          }
        }
      }

      _logging.info('[LlmModelManagement] Successfully fetched and stored ${fetchedModels.length} models');
      return Ok(fetchedModels.length);
    } catch (e, stackTrace) {
      _logging.error('[LlmModelManagement] Unexpected error fetching models', e, stackTrace);
      return Err(ServiceException(
        'Unexpected error fetching models: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Enable a model for use.
  ///
  /// Archived models cannot be enabled.
  Future<Result<void, ServiceException>> enableModel(String modelId) async {
    _logging.debug('[LlmModelManagement] Enabling model: $modelId');

    final result = await _repository.enable(modelId);
    if (result.isErr) {
      final error = result.unwrapErr();
      _logging.error('[LlmModelManagement] Failed to enable model', error);
      return Err(ServiceException(
        'Failed to enable model: ${error.message}',
        error: error,
      ));
    }

    return const Ok(null);
  }

  /// Disable a model.
  Future<Result<void, ServiceException>> disableModel(String modelId) async {
    _logging.debug('[LlmModelManagement] Disabling model: $modelId');

    final result = await _repository.disable(modelId);
    if (result.isErr) {
      final error = result.unwrapErr();
      _logging.error('[LlmModelManagement] Failed to disable model', error);
      return Err(ServiceException(
        'Failed to disable model: ${error.message}',
        error: error,
      ));
    }

    return const Ok(null);
  }

  /// Set a model as the default for its provider.
  ///
  /// This automatically unsets the previous default and enables the model.
  /// Archived models cannot be set as default.
  Future<Result<void, ServiceException>> setDefaultModel(String modelId) async {
    _logging.debug('[LlmModelManagement] Setting model as default: $modelId');

    final result = await _repository.setAsDefault(modelId);
    if (result.isErr) {
      final error = result.unwrapErr();
      _logging.error('[LlmModelManagement] Failed to set default model', error);
      return Err(ServiceException(
        'Failed to set default model: ${error.message}',
        error: error,
      ));
    }

    // Also enable the model when setting as default
    await _repository.enable(modelId);

    return const Ok(null);
  }

  /// Archive a model manually.
  ///
  /// This marks the model as archived, disables it, and removes it from default if set.
  Future<Result<void, ServiceException>> archiveModel(String modelId) async {
    _logging.debug('[LlmModelManagement] Archiving model: $modelId');

    try {
      // Get the model first
      final getResult = await _repository.getById(modelId);
      if (getResult.isErr) {
        final error = getResult.unwrapErr();
        return Err(ServiceException(
          'Model not found: ${error.message}',
          error: error,
        ));
      }

      final model = getResult.unwrap();

      // Update to archive
      final updatedModel = model.copyWith(
        isArchived: true,
        isEnabled: false,
        isDefault: false,
        updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );

      final updateResult = await _repository.update(updatedModel);
      if (updateResult.isErr) {
        final error = updateResult.unwrapErr();
        _logging.error('[LlmModelManagement] Failed to archive model', error);
        return Err(ServiceException(
          'Failed to archive model: ${error.message}',
          error: error,
        ));
      }

      return const Ok(null);
    } catch (e, stackTrace) {
      _logging.error('[LlmModelManagement] Unexpected error archiving model', e, stackTrace);
      return Err(ServiceException(
        'Unexpected error archiving model: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Unarchive a model.
  ///
  /// Makes a previously archived model available again.
  Future<Result<void, ServiceException>> unarchiveModel(String modelId) async {
    _logging.debug('[LlmModelManagement] Unarchiving model: $modelId');

    final result = await _repository.unarchive(modelId);
    if (result.isErr) {
      final error = result.unwrapErr();
      _logging.error('[LlmModelManagement] Failed to unarchive model', error);
      return Err(ServiceException(
        'Failed to unarchive model: ${error.message}',
        error: error,
      ));
    }

    return const Ok(null);
  }

  /// Delete all models for a provider and reset.
  ///
  /// This is useful for completely resetting a provider's models.
  Future<Result<int, ServiceException>> resetProviderModels(
    String providerCode,
  ) async {
    _logging.info('[LlmModelManagement] Resetting models for provider: $providerCode');

    final result = await _repository.deleteByProvider(providerCode);
    if (result.isErr) {
      final error = result.unwrapErr();
      _logging.error('[LlmModelManagement] Failed to reset provider models', error);
      return Err(ServiceException(
        'Failed to reset provider models: ${error.message}',
        error: error,
      ));
    }

    final deletedCount = result.unwrap();
    _logging.info('[LlmModelManagement] Deleted $deletedCount models');
    return Ok(deletedCount);
  }

  /// Get model by ID.
  Future<Result<LlmProviderModel, ServiceException>> getModelById(
    String modelId,
  ) async {
    final result = await _repository.getById(modelId);
    if (result.isErr) {
      final error = result.unwrapErr();
      return Err(ServiceException(
        'Failed to get model: ${error.message}',
        error: error,
      ));
    }

    return Ok(result.unwrap());
  }

  /// Toggle model enabled status.
  Future<Result<void, ServiceException>> toggleModelEnabled(
    String modelId,
  ) async {
    _logging.debug('[LlmModelManagement] Toggling model enabled status: $modelId');

    // Get current state
    final getResult = await _repository.getById(modelId);
    if (getResult.isErr) {
      final error = getResult.unwrapErr();
      return Err(ServiceException(
        'Model not found: ${error.message}',
        error: error,
      ));
    }

    final model = getResult.unwrap();

    // Toggle
    if (model.isEnabled) {
      return await disableModel(modelId);
    } else {
      return await enableModel(modelId);
    }
  }
}
