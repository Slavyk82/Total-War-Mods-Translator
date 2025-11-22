import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/common/result.dart';
import '../models/common/service_exception.dart';
import '../models/domain/translation_memory_entry.dart';
import '../utils/string_similarity.dart';
import 'base_repository.dart';

/// Repository for managing TranslationMemoryEntry entities.
///
/// Provides CRUD operations and custom queries for translation memory,
/// including hash-based lookups and fuzzy matching.
class TranslationMemoryRepository
    extends BaseRepository<TranslationMemoryEntry> {
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
        orderBy: 'quality_score DESC, usage_count DESC',
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

  /// Find translation memory matches using FTS5 fuzzy matching.
  ///
  /// This method uses SQLite FTS5 with BM25 ranking for initial filtering,
  /// then calculates precise Levenshtein similarity on top candidates.
  ///
  /// Performance optimization: FTS5 pre-filters candidates (100-1000x faster than LIKE),
  /// then precise similarity calculation only on top matches.
  ///
  /// [sourceText] - The source text to match against
  /// [targetLanguageId] - Target language ID to filter by
  /// [minConfidence] - Minimum confidence threshold (0.0 to 1.0), defaults to 0.7
  /// [maxCandidates] - Maximum FTS5 candidates to evaluate (default 50)
  ///
  /// Returns [Ok] with list of matches ordered by similarity score,
  /// limited to top 10 results.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>> findMatches(
    String sourceText,
    String targetLanguageId, {
    double minConfidence = 0.7,
    int maxCandidates = 50,
  }) async {
    return executeQuery(() async {
      // Step 1: Use FTS5 to get top candidates based on BM25 ranking
      // This is MUCH faster than LIKE queries (100-1000x improvement)
      final ftsQuery = _buildFts5Query(sourceText);

      // Query FTS5 table for initial candidates using BM25 ranking
      final ftsMaps = await database.rawQuery('''
        SELECT tm.rowid
        FROM translation_memory tm
        INNER JOIN translation_memory_fts fts ON fts.rowid = tm.rowid
        WHERE fts.source_text MATCH ?
          AND tm.target_language_id = ?
        ORDER BY bm25(fts)
        LIMIT ?
      ''', [ftsQuery, targetLanguageId, maxCandidates]);

      if (ftsMaps.isEmpty) {
        return <TranslationMemoryEntry>[];
      }

      // Extract rowids from FTS5 results
      final rowids = ftsMaps.map((row) => row['rowid'] as int).toList();

      // Step 2: Fetch full entries for FTS5 candidates
      final placeholders = List.filled(rowids.length, '?').join(', ');
      final candidateMaps = await database.query(
        tableName,
        where: 'rowid IN ($placeholders)',
        whereArgs: rowids,
      );

      // Step 3: Calculate precise Levenshtein similarity on candidates only
      final matches = <({TranslationMemoryEntry entry, double similarity})>[];

      for (final map in candidateMaps) {
        final entry = fromMap(map);
        final similarity = _calculateSimilarity(sourceText, entry.sourceText);

        if (similarity >= minConfidence) {
          matches.add((entry: entry, similarity: similarity));
        }
      }

      // Step 4: Sort by similarity (descending), then quality + usage
      matches.sort((a, b) {
        final simCompare = b.similarity.compareTo(a.similarity);
        if (simCompare != 0) return simCompare;

        final qualityCompare = (b.entry.qualityScore ?? 0.0)
            .compareTo(a.entry.qualityScore ?? 0.0);
        if (qualityCompare != 0) return qualityCompare;

        return b.entry.usageCount.compareTo(a.entry.usageCount);
      });

      // Return top 10 matches
      return matches.take(10).map((m) => m.entry).toList();
    });
  }

  /// Build FTS5 query from source text.
  ///
  /// Extracts significant words and builds an FTS5 MATCH query.
  /// Filters out very short words and uses OR operator for flexibility.
  String _buildFts5Query(String text) {
    // Extract words, filter short ones, escape quotes
    final words = text
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 3)
        .map((word) => word.replaceAll('"', ''))
        .take(5) // Limit to 5 most significant words
        .toList();

    if (words.isEmpty) {
      // Fallback: use original text with quotes escaped
      return text.replaceAll('"', '');
    }

    // Build OR query: word1 OR word2 OR word3
    return words.join(' OR ');
  }

  /// Calculate simple similarity score between two strings.
  ///
  /// Uses Levenshtein distance normalized by the length of the longer string.
  /// Returns a score from 0.0 (completely different) to 1.0 (identical).
  ///
  /// Delegates to centralized StringSimilarity utility.
  double _calculateSimilarity(String text1, String text2) {
    return StringSimilarity.similarity(text1, text2, caseSensitive: false);
  }

  /// Delete entries with low quality and not recently used (bulk cleanup).
  ///
  /// This method removes TM entries that meet ALL of the following criteria:
  /// - Quality score is below [maxQuality] threshold
  /// - Last used more than [unusedDays] days ago
  ///
  /// [maxQuality] - Maximum quality score for deletion (entries below this are deleted)
  /// [unusedDays] - Minimum days since last use for deletion
  ///
  /// Returns [Ok] with count of deleted entries, [Err] with exception on failure.
  Future<Result<int, TWMTDatabaseException>> deleteByQualityAndAge({
    required double maxQuality,
    required int unusedDays,
  }) async {
    return executeQuery(() async {
      // Calculate cutoff timestamp (current time - unusedDays)
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final cutoffTimestamp = now - (unusedDays * 24 * 60 * 60);

      // Delete entries matching criteria
      final rowsAffected = await database.delete(
        tableName,
        where: 'quality_score < ? AND last_used_at < ?',
        whereArgs: [maxQuality, cutoffTimestamp],
      );

      return rowsAffected;
    });
  }

  /// Get statistics for translation memory entries.
  ///
  /// Returns aggregated statistics including:
  /// - Total number of entries
  /// - Average quality score
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
          COALESCE(AVG(quality_score), 0.0) as avg_quality,
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
  ///
  /// Returns [Ok] with list of entries, [Err] with exception on failure.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      getWithFilters({
    String? targetLanguageId,
    int limit = 50,
    int offset = 0,
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
        orderBy: 'last_used_at DESC',
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
        orderBy: 'quality_score DESC, usage_count DESC',
        limit: 1,
      );

      if (maps.isEmpty) {
        throw TWMTDatabaseException(
            'Translation memory entry not found for hash: $sourceHash');
      }

      return fromMap(maps.first);
    });
  }
}
