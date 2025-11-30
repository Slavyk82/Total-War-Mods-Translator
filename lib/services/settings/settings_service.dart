import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/setting.dart';
import '../../repositories/settings_repository.dart';

/// Settings service for managing application configuration.
///
/// Provides a high-level API for getting and setting application settings.
class SettingsService {
  final SettingsRepository _repository;

  SettingsService(this._repository);

  /// Get a setting by key.
  Future<Result<Setting?, TWMTDatabaseException>> getSetting(String key) async {
    return await _repository.getByKey(key);
  }

  /// Get a string setting value.
  ///
  /// Returns the value if found and is a string, otherwise returns the default value.
  Future<String> getString(String key, {String defaultValue = ''}) async {
    final result = await _repository.getByKey(key);
    return result.when(
      ok: (setting) {
        if (setting.valueType != SettingValueType.string) return defaultValue;
        return setting.value;
      },
      err: (_) => defaultValue,
    );
  }

  /// Get an integer setting value.
  ///
  /// Returns the value if found and is an integer, otherwise returns the default value.
  Future<int> getInt(String key, {int defaultValue = 0}) async {
    final result = await _repository.getByKey(key);
    return result.when(
      ok: (setting) {
        if (setting.valueType != SettingValueType.integer) return defaultValue;
        return int.tryParse(setting.value) ?? defaultValue;
      },
      err: (_) => defaultValue,
    );
  }

  /// Get a boolean setting value.
  ///
  /// Returns the value if found and is a boolean, otherwise returns the default value.
  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final result = await _repository.getByKey(key);
    return result.when(
      ok: (setting) {
        if (setting.valueType != SettingValueType.boolean) return defaultValue;
        return setting.value.toLowerCase() == 'true';
      },
      err: (_) => defaultValue,
    );
  }

  /// Get a JSON setting value.
  ///
  /// Returns the value if found and is JSON, otherwise returns the default value.
  Future<String> getJson(String key, {String defaultValue = '{}'}) async {
    final result = await _repository.getByKey(key);
    return result.when(
      ok: (setting) {
        if (setting.valueType != SettingValueType.json) return defaultValue;
        return setting.value;
      },
      err: (_) => defaultValue,
    );
  }

  /// Set a string setting value.
  Future<Result<void, TWMTDatabaseException>> setString(
    String key,
    String value,
  ) async {
    return await _repository.setValue(key, value, SettingValueType.string);
  }

  /// Set an integer setting value.
  Future<Result<void, TWMTDatabaseException>> setInt(String key, int value) async {
    return await _repository.setValue(
      key,
      value.toString(),
      SettingValueType.integer,
    );
  }

  /// Set a boolean setting value.
  Future<Result<void, TWMTDatabaseException>> setBool(
    String key,
    bool value,
  ) async {
    return await _repository.setValue(
      key,
      value.toString(),
      SettingValueType.boolean,
    );
  }

  /// Set a JSON setting value.
  Future<Result<void, TWMTDatabaseException>> setJson(
    String key,
    String jsonValue,
  ) async {
    return await _repository.setValue(key, jsonValue, SettingValueType.json);
  }

  /// Get the active translation provider ID.
  Future<String?> getActiveProviderId() async {
    return await getString('active_translation_provider_id');
  }

  /// Set the active translation provider ID.
  Future<Result<void, TWMTDatabaseException>> setActiveProviderId(
    String providerId,
  ) async {
    return await setString('active_translation_provider_id', providerId);
  }

  /// Get the default game installation ID.
  Future<String?> getDefaultGameId() async {
    final value = await getString('default_game_installation_id');
    return value.isEmpty ? null : value;
  }

  /// Set the default game installation ID.
  Future<Result<void, TWMTDatabaseException>> setDefaultGameId(
    String gameId,
  ) async {
    return await setString('default_game_installation_id', gameId);
  }

  /// Get the default batch size.
  Future<int> getDefaultBatchSize() async {
    return await getInt('default_batch_size', defaultValue: 25);
  }

  /// Set the default batch size.
  Future<Result<void, TWMTDatabaseException>> setDefaultBatchSize(
    int size,
  ) async {
    if (size < 1 || size > 100) {
      return Err(
        TWMTDatabaseException('Batch size must be between 1 and 100'),
      );
    }
    return await setInt('default_batch_size', size);
  }

  /// Get the default parallel batches count.
  Future<int> getDefaultParallelBatches() async {
    return await getInt('default_parallel_batches', defaultValue: 5);
  }

  /// Set the default parallel batches count.
  Future<Result<void, TWMTDatabaseException>> setDefaultParallelBatches(
    int count,
  ) async {
    if (count < 1 || count > 20) {
      return Err(
        TWMTDatabaseException('Parallel batches must be between 1 and 20'),
      );
    }
    return await setInt('default_parallel_batches', count);
  }

  /// Get the RPFM executable path.
  Future<String?> getRpfmPath() async {
    final value = await getString('rpfm_path');
    return value.isEmpty ? null : value;
  }

  /// Set the RPFM executable path.
  Future<Result<void, TWMTDatabaseException>> setRpfmPath(
    String path,
  ) async {
    return await setString('rpfm_path', path);
  }

  /// Get the Total War game for RPFM operations.
  /// Returns the configured game or 'warhammer_3' as default.
  Future<String> getTotalWarGame() async {
    final value = await getString('total_war_game');
    return value.isEmpty ? 'warhammer_3' : value;
  }

  /// Set the Total War game for RPFM operations.
  /// Valid values: pharaoh_dynasties, pharaoh, warhammer_3, troy, three_kingdoms,
  /// warhammer_2, warhammer, thrones_of_britannia, attila, rome_2, shogun_2,
  /// napoleon, empire, arena
  Future<Result<void, TWMTDatabaseException>> setTotalWarGame(
    String game,
  ) async {
    return await setString('total_war_game', game);
  }

  /// Get all settings.
  Future<Result<List<Setting>, TWMTDatabaseException>> getAllSettings() async {
    return await _repository.getAll();
  }
}
