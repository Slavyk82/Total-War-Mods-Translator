import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/llm_provider_model.dart';
import '../services/llm/utils/model_validator.dart';
import 'base_repository.dart';

/// Repository for managing LLM Provider Model entities.
///
/// Provides CRUD operations and custom queries for LLM models,
/// including filtering by provider, enabled status, and archival state.
class LlmProviderModelRepository extends BaseRepository<LlmProviderModel> {
  @override
  String get tableName => 'llm_provider_models';

  @override
  LlmProviderModel fromMap(Map<String, dynamic> map) {
    return LlmProviderModel.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(LlmProviderModel entity) {
    return entity.toJson();
  }

  @override
  Future<Result<LlmProviderModel, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('LLM model not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'provider_code ASC, model_id ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<LlmProviderModel, TWMTDatabaseException>> insert(
      LlmProviderModel entity) async {
    // Validate provider/model compatibility
    final validationError = LlmModelValidator.validate(
      entity.providerCode,
      entity.modelId,
    );
    if (validationError != null) {
      return Err(TWMTDatabaseException(validationError));
    }

    return executeQuery(() async {
      final map = toMap(entity);
      await database.insert(
        tableName,
        map,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      return entity;
    });
  }

  @override
  Future<Result<LlmProviderModel, TWMTDatabaseException>> update(
      LlmProviderModel entity) async {
    // Validate provider/model compatibility
    final validationError = LlmModelValidator.validate(
      entity.providerCode,
      entity.modelId,
    );
    if (validationError != null) {
      return Err(TWMTDatabaseException(validationError));
    }

    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'LLM model not found for update: ${entity.id}');
      }

      return entity;
    });
  }

  @override
  Future<Result<void, TWMTDatabaseException>> delete(String id) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('LLM model not found for deletion: $id');
      }
    });
  }

  /// Get all models for a specific provider.
  ///
  /// Returns [Ok] with list of models for the provider, ordered by model_id.
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>>
      getByProvider(String providerCode) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'provider_code = ?',
        whereArgs: [providerCode],
        orderBy: 'model_id ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all enabled models for a specific provider (excluding archived).
  ///
  /// Returns [Ok] with list of enabled, non-archived models.
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>>
      getEnabledByProvider(String providerCode) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'provider_code = ? AND is_enabled = 1 AND is_archived = 0',
        whereArgs: [providerCode],
        orderBy: 'model_id ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get all available (non-archived) models for a specific provider.
  ///
  /// Returns [Ok] with list of non-archived models, regardless of enabled status.
  Future<Result<List<LlmProviderModel>, TWMTDatabaseException>>
      getAvailableByProvider(String providerCode) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'provider_code = ? AND is_archived = 0',
        whereArgs: [providerCode],
        orderBy: 'model_id ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get the default model for a specific provider.
  ///
  /// Returns [Ok] with the default model if it belongs to this provider, null otherwise.
  Future<Result<LlmProviderModel?, TWMTDatabaseException>> getDefaultByProvider(
      String providerCode) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'provider_code = ? AND is_default = 1 AND is_archived = 0',
        whereArgs: [providerCode],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Get the global default model (only one can exist across all providers).
  ///
  /// Returns [Ok] with the default model, null if none is set.
  Future<Result<LlmProviderModel?, TWMTDatabaseException>> getGlobalDefault() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'is_default = 1 AND is_archived = 0',
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Get a model by provider and model ID.
  ///
  /// Returns [Ok] with the model if found, [Err] if not found.
  Future<Result<LlmProviderModel?, TWMTDatabaseException>>
      getByProviderAndModelId(String providerCode, String modelId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'provider_code = ? AND model_id = ?',
        whereArgs: [providerCode, modelId],
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Bulk insert or update models.
  ///
  /// This method is optimized for inserting/updating multiple models at once,
  /// which is useful when fetching models from provider APIs.
  ///
  /// Uses REPLACE conflict algorithm to update existing models or insert new ones.
  /// Validates all models before inserting; fails fast on first invalid model.
  Future<Result<void, TWMTDatabaseException>> upsertMany(
      List<LlmProviderModel> models) async {
    // Validate all models before transaction
    for (final model in models) {
      final validationError = LlmModelValidator.validate(
        model.providerCode,
        model.modelId,
      );
      if (validationError != null) {
        return Err(TWMTDatabaseException(
          'Invalid model in batch: ${model.modelId} - $validationError',
        ));
      }
    }

    return executeTransaction((txn) async {
      final batch = txn.batch();

      for (final model in models) {
        final map = toMap(model);
        batch.insert(
          tableName,
          map,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await batch.commit(noResult: true);
    });
  }

  /// Archive models that haven't been seen in a recent fetch.
  ///
  /// This method marks models as archived if they weren't updated after
  /// the given timestamp. This is used to automatically archive models
  /// that are no longer returned by the provider's API.
  ///
  /// [providerCode] - Provider to check
  /// [sinceTimestamp] - Unix timestamp; models not updated after this are archived
  ///
  /// Returns [Ok] with number of models archived.
  Future<Result<int, TWMTDatabaseException>> archiveStaleModels(
    String providerCode,
    int sinceTimestamp,
  ) async {
    return executeQuery(() async {
      final rowsAffected = await database.update(
        tableName,
        {
          'is_archived': 1,
          'is_enabled': 0, // Disable when archiving
          'is_default': 0, // Remove default when archiving
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where:
            'provider_code = ? AND last_fetched_at < ? AND is_archived = 0',
        whereArgs: [providerCode, sinceTimestamp],
      );

      return rowsAffected;
    });
  }

  /// Unarchive a model (make it available again).
  ///
  /// This can be used if a previously archived model becomes available again.
  Future<Result<void, TWMTDatabaseException>> unarchive(String id) async {
    return executeQuery(() async {
      final rowsAffected = await database.update(
        tableName,
        {
          'is_archived': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('LLM model not found for unarchive: $id');
      }
    });
  }

  /// Set a model as the global default.
  ///
  /// Only one model can be default at a time across all providers.
  /// This unsets any previous default before setting the new one.
  Future<Result<void, TWMTDatabaseException>> setAsDefault(String id) async {
    return executeTransaction((txn) async {
      // First, verify the model exists and is not archived
      final maps = await txn.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('LLM model not found: $id');
      }

      final model = fromMap(maps.first);
      if (model.isArchived) {
        throw TWMTDatabaseException(
            'Cannot set archived model as default: $id');
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Clear all existing defaults across ALL providers
      await txn.update(
        tableName,
        {
          'is_default': 0,
          'updated_at': now,
        },
        where: 'is_default = 1',
      );

      // Set the new default
      final rowsAffected = await txn.update(
        tableName,
        {
          'is_default': 1,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException(
            'LLM model not found for set as default: $id');
      }
    });
  }

  /// Enable a model.
  ///
  /// Archived models cannot be enabled.
  Future<Result<void, TWMTDatabaseException>> enable(String id) async {
    return executeQuery(() async {
      // First, verify the model exists and is not archived
      final modelResult = await getById(id);
      if (modelResult.isErr) {
        throw modelResult.unwrapErr();
      }

      final model = modelResult.unwrap();
      if (model.isArchived) {
        throw TWMTDatabaseException('Cannot enable archived model: $id');
      }

      final rowsAffected = await database.update(
        tableName,
        {
          'is_enabled': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('LLM model not found for enable: $id');
      }
    });
  }

  /// Disable a model.
  Future<Result<void, TWMTDatabaseException>> disable(String id) async {
    return executeQuery(() async {
      final rowsAffected = await database.update(
        tableName,
        {
          'is_enabled': 0,
          'updated_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('LLM model not found for disable: $id');
      }
    });
  }

  /// Delete all models for a specific provider.
  ///
  /// This is useful for resetting a provider's models.
  Future<Result<int, TWMTDatabaseException>> deleteByProvider(
      String providerCode) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'provider_code = ?',
        whereArgs: [providerCode],
      );

      return rowsAffected;
    });
  }
}
