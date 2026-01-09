import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_memory_entry.dart';
import 'base_repository.dart';
import 'mixins/translation_memory_batch_mixin.dart';
import 'mixins/translation_memory_fts_mixin.dart';
import 'mixins/translation_memory_migration_mixin.dart';

/// Repository for managing TranslationMemoryEntry entities.
///
/// Provides CRUD operations and custom queries for translation memory,
/// including hash-based lookups and fuzzy matching.
///
/// Complex operations are delegated to mixins:
/// - [TranslationMemoryFtsMixin]: FTS5 search and fuzzy matching
/// - [TranslationMemoryBatchMixin]: Batch insert/upsert operations
/// - [TranslationMemoryMigrationMixin]: Legacy hash migration operations
class TranslationMemoryRepository extends BaseRepository<TranslationMemoryEntry>
    with
        TranslationMemoryFtsMixin,
        TranslationMemoryBatchMixin,
        TranslationMemoryMigrationMixin {
  @override
  String get tableName => 'translation_memory';

  @override
  TranslationMemoryEntry fromMap(Map<String, dynamic> map) {
    return TranslationMemoryEntry.fromJson(map);
  }

  @override
  Map<String, dynamic> toMap(TranslationMemoryEntry entity) {
    return entity.toJson();
  }

  @override
  Future<Result<TranslationMemoryEntry, TWMTDatabaseException>> getById(
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
            'Translation memory entry not found with id: $id');
      }

      return fromMap(maps.first);
    });
  }

  @override
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      getAll() async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        orderBy: 'last_used_at DESC',
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  @override
  Future<Result<TranslationMemoryEntry, TWMTDatabaseException>> insert(
      TranslationMemoryEntry entity) async {
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
  Future<Result<TranslationMemoryEntry, TWMTDatabaseException>> update(
      TranslationMemoryEntry entity) async {
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
            'Translation memory entry not found for update: ${entity.id}');
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
            'Translation memory entry not found for deletion: $id');
      }
    });
  }

  /// Find a translation memory entry by exact hash match.
  ///
  /// Returns [Ok] with the entry if found, [Err] with exception if not found.
  Future<Result<TranslationMemoryEntry, TWMTDatabaseException>> findByHash(
      String sourceHash, String targetLanguageId) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'source_hash = ? AND target_language_id = ?',
        whereArgs: [sourceHash, targetLanguageId],
        orderBy: 'usage_count DESC',
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation memory entry not found for hash: $sourceHash and language: $targetLanguageId');
      }

      // Update usage statistics
      final entry = fromMap(maps.first);
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await database.update(
        tableName,
        {
          'usage_count': entry.usageCount + 1,
          'last_used_at': now,
        },
        where: 'id = ?',
        whereArgs: [entry.id],
      );

      return entry;
    });
  }

  /// Delete entries not recently used (bulk cleanup).
  ///
  /// This method removes TM entries not used within [unusedDays] days.
  ///
  /// [unusedDays] - Minimum days since last use
  ///
  /// Returns [Ok] with count of deleted entries, [Err] with exception on failure.
  Future<Result<int, TWMTDatabaseException>> deleteByAge({
    required int unusedDays,
  }) async {
    return executeQuery(() async {
      if (unusedDays <= 0) {
        return 0;
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final cutoffTimestamp = now - (unusedDays * 24 * 60 * 60);

      final rowsAffected = await database.rawDelete(
        '''
        DELETE FROM $tableName
        WHERE COALESCE(last_used_at, 0) < ?
        ''',
        [cutoffTimestamp],
      );

      return rowsAffected;
    });
  }

  /// Count entries that would be deleted by cleanup criteria.
  ///
  /// Used for diagnostics/preview before actual deletion.
  Future<Result<Map<String, int>, TWMTDatabaseException>>
      countCleanupCandidates({
    required int unusedDays,
  }) async {
    return executeQuery(() async {
      if (unusedDays <= 0) {
        return {
          'willBeDeleted': 0,
          'unusedOnly': 0,
        };
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final cutoffTimestamp = now - (unusedDays * 24 * 60 * 60);

      // Count entries not used recently
      final unusedResult = await database.rawQuery(
        '''
        SELECT COUNT(*) as count FROM $tableName
        WHERE COALESCE(last_used_at, 0) < ?
        ''',
        [cutoffTimestamp],
      );

      return {
        'willBeDeleted': unusedResult.first['count'] as int,
        'unusedOnly': unusedResult.first['count'] as int,
      };
    });
  }

  /// Get statistics for translation memory entries.
  ///
  /// Returns aggregated statistics including:
  /// - Total number of entries
  /// - Total usage count
  /// - Optional filtering by target language
  ///
  /// [targetLanguageId] - Optional target language filter
  ///
  /// Returns [Ok] with statistics map, [Err] with exception on failure.
  Future<Result<Map<String, dynamic>, TWMTDatabaseException>> getStatistics({
    String? targetLanguageId,
  }) async {
    return executeQuery(() async {
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      if (targetLanguageId != null) {
        whereConditions.add('target_language_id = ?');
        whereArgs.add(targetLanguageId);
      }

      final whereClause =
          whereConditions.isEmpty ? null : whereConditions.join(' AND ');

      // Get aggregated statistics
      final result = await database.rawQuery('''
        SELECT
          COUNT(*) as total_entries,
          COALESCE(SUM(usage_count), 0) as total_usage
        FROM $tableName
        ${whereClause != null ? 'WHERE $whereClause' : ''}
      ''', whereArgs);

      return result.first;
    });
  }

  /// Count entries by target language.
  ///
  /// Returns a map of target language IDs to entry counts.
  ///
  /// Returns [Ok] with language counts, [Err] with exception on failure.
  Future<Result<Map<String, int>, TWMTDatabaseException>>
      getEntriesByLanguage() async {
    return executeQuery(() async {
      final result = await database.rawQuery('''
        SELECT
          target_language_id,
          COUNT(*) as count
        FROM $tableName
        GROUP BY target_language_id
      ''');

      return Map.fromEntries(
        result.map((row) => MapEntry(
              row['target_language_id'] as String,
              row['count'] as int,
            )),
      );
    });
  }

  /// Get entries with pagination and optional filtering.
  ///
  /// [targetLanguageId] - Optional target language filter
  /// [limit] - Maximum number of results (default: 50)
  /// [offset] - Pagination offset (default: 0)
  /// [orderBy] - SQL ORDER BY clause (default: 'usage_count DESC')
  ///
  /// Returns [Ok] with list of entries, [Err] with exception on failure.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      getWithFilters({
    String? targetLanguageId,
    int limit = 50,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async {
    return executeQuery(() async {
      final whereConditions = <String>[];
      final whereArgs = <dynamic>[];

      if (targetLanguageId != null) {
        whereConditions.add('target_language_id = ?');
        whereArgs.add(targetLanguageId);
      }

      final whereClause =
          whereConditions.isEmpty ? null : whereConditions.join(' AND ');

      final maps = await database.query(
        tableName,
        where: whereClause,
        whereArgs: whereArgs.isEmpty ? null : whereArgs,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Find an entry by source hash (for deduplication).
  ///
  /// [sourceHash] - Hash of normalized source text
  /// [targetLanguageId] - Target language ID
  ///
  /// Returns [Ok] with entry if found, [Err] if not found or on error.
  Future<Result<TranslationMemoryEntry, TWMTDatabaseException>>
      findBySourceHash(
    String sourceHash,
    String targetLanguageId,
  ) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: 'source_hash = ? AND target_language_id = ?',
        whereArgs: [sourceHash, targetLanguageId],
        orderBy: 'usage_count DESC',
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation memory entry not found for hash: $sourceHash');
      }

      return fromMap(maps.first);
    });
  }

  /// Delete all translation memory entries for a specific language.
  ///
  /// This is used when deleting a custom language to clean up TM entries
  /// that reference it (either as source or target language).
  ///
  /// [languageId] - The language ID to delete entries for
  ///
  /// Returns [Ok] with count of deleted entries, [Err] with exception on failure.
  Future<Result<int, TWMTDatabaseException>> deleteByLanguageId(
    String languageId,
  ) async {
    return executeQuery(() async {
      final rowsAffected = await database.delete(
        tableName,
        where: 'source_language_id = ? OR target_language_id = ?',
        whereArgs: [languageId, languageId],
      );

      return rowsAffected;
    });
  }
}
