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
  /// Note: Does NOT update usage statistics. Callers should use
  /// [incrementUsageCountBatch] separately after collecting all matches.
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

      return fromMap(maps.first);
    });
  }

  /// Batch increment usage counts for multiple TM entries in a single transaction.
  ///
  /// Each entry in [usageCounts] maps an entry ID to the increment value.
  /// Uses direct SQL UPDATE (no SELECT) for maximum performance.
  ///
  /// Returns [Ok] with number of entries updated, [Err] on failure.
  Future<Result<int, TWMTDatabaseException>> incrementUsageCountBatch(
    Map<String, int> usageCounts,
  ) async {
    if (usageCounts.isEmpty) {
      return const Ok(0);
    }

    return executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Group ids by the increment delta so we can flush one UPDATE per delta
      // instead of one per entry. In practice the vast majority of deltas are
      // +1, so this collapses to a single statement for a TM lookup batch.
      final byDelta = <int, List<String>>{};
      for (final entry in usageCounts.entries) {
        (byDelta[entry.value] ??= <String>[]).add(entry.key);
      }

      var updatedCount = 0;
      for (final group in byDelta.entries) {
        final delta = group.key;
        final ids = group.value;
        final placeholders = List.filled(ids.length, '?').join(',');
        final rowsAffected = await txn.rawUpdate(
          'UPDATE $tableName '
          'SET usage_count = usage_count + ?, '
          '    last_used_at = ?, '
          '    updated_at = ? '
          'WHERE id IN ($placeholders)',
          [delta, now, now, ...ids],
        );
        updatedCount += rowsAffected;
      }

      return updatedCount;
    });
  }

  /// Delete entries not recently used (bulk cleanup).
  ///
  /// This method removes TM entries not used within [unusedDays] days.
  ///
  /// [unusedDays] - Minimum days since last use
  ///
  /// Returns [Ok] with a record containing the number of deleted entries and
  /// the sum of their `usage_count` (so lifetime reuse stats can be archived
  /// before the rows vanish).
  Future<Result<({int deletedCount, int deletedUsageSum}),
      TWMTDatabaseException>> deleteByAge({
    required int unusedDays,
  }) async {
    return executeQuery(() async {
      if (unusedDays <= 0) {
        return (deletedCount: 0, deletedUsageSum: 0);
      }

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final cutoffTimestamp = now - (unusedDays * 24 * 60 * 60);

      // Capture the usage sum of rows about to be deleted so we can forward
      // it to the lifetime archive counters maintained by the service layer.
      final sumRow = await database.rawQuery(
        '''
        SELECT COALESCE(SUM(usage_count), 0) AS usage_sum FROM $tableName
        WHERE COALESCE(last_used_at, 0) < ?
        ''',
        [cutoffTimestamp],
      );
      final usageSum = (sumRow.first['usage_sum'] as int?) ?? 0;

      final rowsAffected = await database.rawDelete(
        '''
        DELETE FROM $tableName
        WHERE COALESCE(last_used_at, 0) < ?
        ''',
        [cutoffTimestamp],
      );

      return (deletedCount: rowsAffected, deletedUsageSum: usageSum);
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

  /// Count entries matching optional filters.
  ///
  /// [targetLanguageId] - Optional target language filter
  ///
  /// Uses SELECT COUNT(*) so the whole table never has to be loaded.
  Future<Result<int, TWMTDatabaseException>> countWithFilters({
    String? targetLanguageId,
  }) async {
    return executeQuery(() async {
      final whereArgs = <dynamic>[];
      final whereClause = targetLanguageId != null
          ? 'WHERE target_language_id = ?'
          : '';
      if (targetLanguageId != null) {
        whereArgs.add(targetLanguageId);
      }

      final result = await database.rawQuery(
        'SELECT COUNT(*) as count FROM $tableName $whereClause',
        whereArgs.isEmpty ? null : whereArgs,
      );

      return (result.first['count'] as int?) ?? 0;
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

  /// LIKE-based fallback search used when FTS5 is unavailable.
  ///
  /// Uses indexed columns with bounded LIMIT — streaming, not in-memory scan.
  /// Not as fast as FTS5 BM25 but O(n) with early termination via LIMIT,
  /// not O(n) with full table load into RAM.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      searchByLike({
    required String searchText,
    required String searchScope,
    String? targetLanguageId,
    int limit = 50,
  }) async {
    return executeQuery(() async {
      final pattern = '%${searchText.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      final whereClauses = <String>[];
      final args = <Object?>[];

      if (searchScope == 'source' || searchScope == 'both') {
        whereClauses.add('source_text LIKE ? ESCAPE ?');
        args.addAll([pattern, r'\']);
      }
      if (searchScope == 'target' || searchScope == 'both') {
        whereClauses.add('translated_text LIKE ? ESCAPE ?');
        args.addAll([pattern, r'\']);
      }

      var where = '(${whereClauses.join(' OR ')})';
      if (targetLanguageId != null) {
        where = '$where AND target_language_id = ?';
        args.add(targetLanguageId);
      }

      final maps = await database.query(
        tableName,
        where: where,
        whereArgs: args,
        orderBy: 'usage_count DESC',
        limit: limit,
      );

      return maps.map(fromMap).toList();
    });
  }

  /// Stream TM entries in fixed-size pages. Caller is responsible for writing
  /// each chunk to disk before requesting the next page — this avoids loading
  /// the full TM into RAM (500+ MB at 6M rows).
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>> getPage({
    required int offset,
    required int pageSize,
    String? targetLanguageId,
  }) async {
    return executeQuery(() async {
      final maps = await database.query(
        tableName,
        where: targetLanguageId != null ? 'target_language_id = ?' : null,
        whereArgs: targetLanguageId != null ? [targetLanguageId] : null,
        orderBy: 'id ASC',
        limit: pageSize,
        offset: offset,
      );
      return maps.map(fromMap).toList();
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
