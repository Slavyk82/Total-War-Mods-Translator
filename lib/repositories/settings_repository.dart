import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/setting.dart';
import 'base_repository.dart';

/// Repository for managing Setting entities.
///
/// Provides CRUD operations and custom queries for application settings,
/// including key-based lookups and convenience methods for value operations.
class SettingsRepository extends BaseRepository<Setting> {
  @override
  String get tableName => 'settings';

  @override
  Setting fromMap(Map<String, dynamic> map) {
    return Setting.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(Setting entity) {
    return entity.toJson();
  }

  @override
  Future<Result<Setting, TWMTDatabaseException>> getById(String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Setting not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<Setting>, TWMTDatabaseException>> getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'key ASC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<Setting, TWMTDatabaseException>> insert(Setting entity) async {
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
  Future<Result<Setting, TWMTDatabaseException>> update(Setting entity) async {
    return executeQuery(() async {
      final map = toMap(entity);
      final rowsAffected = await database.update(
        tableName,
        map,
        where: 'id = ?',
        whereArgs: [entity.id],
      );

      if (rowsAffected == 0) {
        throw TWMTDatabaseException('Setting not found for update: ${entity.id}');
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
        throw TWMTDatabaseException('Setting not found for deletion: $id');
      }
    });
  }

  /// Get a setting by its key.
  ///
  /// Returns [Ok] with the setting if found, [Err] with exception if not found.
  Future<Result<Setting, TWMTDatabaseException>> getByKey(String key) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Setting not found with key: $key');
      }

      return fromMap(maps.first);
    });
  }

  /// Get a setting value by key.
  ///
  /// Returns [Ok] with the value string if found, [Err] with exception if not found.
  Future<Result<String, TWMTDatabaseException>> getValue(String key) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        columns: ['value'],
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException('Setting not found with key: $key');
      }

      return maps.first['value'] as String;
    });
  }

  /// Set a setting value by key.
  ///
  /// If the setting exists, it will be updated. If it doesn't exist,
  /// a new setting will be created.
  ///
  /// Returns [Ok] with the setting entity, [Err] with exception if operation fails.
  Future<Result<Setting, TWMTDatabaseException>> setValue(
    String key,
    String value,
    SettingValueType valueType,
  ) async {
    return executeQuery(() async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Try to find existing setting
      final existingMaps = await database.query(
        tableName,
        where: 'key = ?',
        whereArgs: [key],
        limit: 1,
      );

      Setting setting;

      if (existingMaps.isNotEmpty) {
        // Update existing setting
        final existing = fromMap(existingMaps.first);
        setting = existing.copyWith(
          value: value,
          valueType: valueType,
          updatedAt: now,
        );

        await database.update(
          tableName,
          toMap(setting),
          where: 'id = ?',
          whereArgs: [existing.id],
        );
      } else {
        // Create new setting
        // Generate a simple UUID-like ID (in production, use uuid package)
        final id = '${DateTime.now().millisecondsSinceEpoch}-$key';

        setting = Setting(
          id: id,
          key: key,
          value: value,
          valueType: valueType,
          updatedAt: now,
        );

        await database.insert(
          tableName,
          toMap(setting),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      }

      return setting;
    });
  }
}
