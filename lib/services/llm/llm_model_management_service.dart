import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/llm_provider_model.dart';
import '../../repositories/llm_provider_model_repository.dart';
import '../shared/logging_service.dart';

/// Service for managing LLM provider models.
///
/// Models are seeded in the database via migration. This service handles
/// model enabled/disabled/default status management.
class LlmModelManagementService {
  final LlmProviderModelRepository _repository;
  final LoggingService _logging;

  LlmModelManagementService(
    this._repository,
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

  /// Get the global default model (only one can exist across all providers).
  Future<Result<LlmProviderModel?, TWMTDatabaseException>> getGlobalDefaultModel() async {
    _logging.debug('[LlmModelManagement] Getting global default model');
    return await _repository.getGlobalDefault();
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
