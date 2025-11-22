import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_version_history.dart';
import 'base_repository.dart';

/// Repository for managing TranslationVersionHistory entities
///
/// Provides CRUD operations and custom queries for translation version history,
/// including filtering by version, time ranges, and change attribution.
class TranslationVersionHistoryRepository
    extends BaseRepository<TranslationVersionHistory> {
  @override
  String get tableName => 'translation_version_history';

  @override
  TranslationVersionHistory fromMap(Map<String, dynamic> map) {
    return TranslationVersionHistory.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationVersionHistory entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationVersionHistory, TWMTDatabaseException>> getById(
      String id) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation version history not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationVersionHistory>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationVersionHistory, TWMTDatabaseException>> insert(
      TranslationVersionHistory entity) async {
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
  Future<Result<TranslationVersionHistory, TWMTDatabaseException>> update(
      TranslationVersionHistory entity) async {
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
            'Translation version history not found for update: ${entity.id}');
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
        throw TWMTDatabaseException(
            'Translation version history not found for deletion: $id');
      }
    });
  }

  /// Get all history entries for a specific translation version
  ///
  /// Returns entries ordered by creation date (newest first).
  Future<Result<List<TranslationVersionHistory>, TWMTDatabaseException>>
      getByVersion(String versionId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'version_id = ?',
        whereArgs: [versionId],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get history entries for a version with pagination
  ///
  /// [versionId] - ID of the translation version
  /// [limit] - Maximum number of entries to return
  /// [offset] - Number of entries to skip
  Future<Result<List<TranslationVersionHistory>, TWMTDatabaseException>>
      getByVersionPaginated(
    String versionId, {
    int limit = 50,
    int offset = 0,
  }) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'version_id = ?',
        whereArgs: [versionId],
        orderBy: 'created_at DESC',
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Get history entries by change attribution
  ///
  /// [changedBy] - Who made the change ('user', 'provider_anthropic', etc.)
  Future<Result<List<TranslationVersionHistory>, TWMTDatabaseException>>
      getByChangedBy(String changedBy) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'changed_by = ?',
        whereArgs: [changedBy],
        orderBy: 'created_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Delete history entries older than specified timestamp
  ///
  /// [timestamp] - Unix timestamp; entries before this will be deleted
  ///
  /// Returns number of entries deleted
  Future<Result<int, TWMTDatabaseException>> deleteOlderThan(
      int timestamp) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'created_at < ?',
        whereArgs: [timestamp],
      );

      return rowsAffected;
    });
  }

  /// Count total history entries
  Future<Result<int, TWMTDatabaseException>> count() async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName',
      );

      return result.first['count'] as int;
    });
  }

  /// Count history entries for a specific version
  Future<Result<int, TWMTDatabaseException>> countByVersion(
      String versionId) async {
    return executeQuery(() async {
      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName WHERE version_id = ?',
        [versionId],
      );

      return result.first['count'] as int;
    });
  }

  /// Get statistics about history entries
  ///
  /// Returns counts by change attribution type
  Future<Result<Map<String, int>, TWMTDatabaseException>>
      getStatistics() async {
    return executeQuery(() async {
      final result = await database.rawQuery('''
        SELECT
          changed_by,
          COUNT(*) as count
        FROM $tableName
        GROUP BY changed_by
      ''');

      final stats = <String, int>{};
      for (final row in result) {
        stats[row['changed_by'] as String] = row['count'] as int;
      }

      return stats;
    });
  }

  /// Get the most recent history entry for a version
  Future<Result<TranslationVersionHistory?, TWMTDatabaseException>>
      getMostRecent(String versionId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'version_id = ?',
        whereArgs: [versionId],
        orderBy: 'created_at DESC',
        limit: 1,
      );

      if (maps.isEmpty) {
        return null;
      }

      return fromMap(maps.first);
    });
  }

  /// Get time range of history entries
  ///
  /// Returns earliest and latest timestamps
  Future<Result<Map<String, int?>, TWMTDatabaseException>>
      getTimeRange() async {
    return executeQuery(() async {
      final result = await database.rawQuery('''
        SELECT
          MIN(created_at) as oldest,
          MAX(created_at) as newest
        FROM $tableName
      ''');

      final row = result.first;
      return {
        'oldest': row['oldest'] as int?,
        'newest': row['newest'] as int?,
      };
    });
  }

  /// Count revert operations
  ///
  /// Counts entries where change_reason contains 'Reverted' or 'revert'
  Future<Result<int, TWMTDatabaseException>> countReverts() async {
    return executeQuery(() async {
      final result = await database.rawQuery('''
        SELECT COUNT(*) as count
        FROM $tableName
        WHERE change_reason LIKE '%Reverted%'
           OR change_reason LIKE '%revert%'
      ''');

      return result.first['count'] as int;
    });
  }
}
