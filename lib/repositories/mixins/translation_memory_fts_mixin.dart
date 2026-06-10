import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../../models/domain/translation_memory_entry.dart';
import '../../utils/string_similarity.dart';

/// Mixin providing FTS5 full-text search operations for translation memory.
///
/// Extracts FTS5 search logic from the main repository to maintain
/// single responsibility and keep file sizes manageable.
///
/// Includes:
/// - [findMatches]: Fuzzy matching with Levenshtein similarity
/// - [searchFts5]: Full-text search across source/target text
mixin TranslationMemoryFtsMixin {
  /// Database instance - must be provided by implementing class
  Database get database;

  /// Table name - must be provided by implementing class
  String get tableName;

  /// Convert database map to entity - must be provided by implementing class
  TranslationMemoryEntry fromMap(Map<String, dynamic> map);

  /// Execute a query with error handling - must be provided by implementing class
  Future<Result<R, TWMTDatabaseException>> executeQuery<R>(
    Future<R> Function() query,
  );

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
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      findMatches(
    String sourceText,
    String targetLanguageId, {
    double minConfidence = 0.7,
    int maxCandidates = 50,
  }) async {
    return executeQuery(() async {
      // Step 1: Use FTS5 to get top candidates based on BM25 ranking
      // This is MUCH faster than LIKE queries (100-1000x improvement)
      final ftsQuery = _buildFts5Query(sourceText);

      // No usable tokens (empty/whitespace/punctuation-only input):
      // short-circuit instead of sending an invalid MATCH expression to FTS5.
      if (ftsQuery.isEmpty) {
        return <TranslationMemoryEntry>[];
      }

      // Query FTS5 table for initial candidates using BM25 ranking.
      // bm25() requires the FTS5 table's hidden column (its real name, not
      // the join alias) and is negative — more negative means more relevant —
      // so ascending order yields best candidates first.
      final ftsMaps = await database.rawQuery('''
        SELECT tm.rowid
        FROM translation_memory tm
        INNER JOIN translation_memory_fts fts ON fts.rowid = tm.rowid
        WHERE fts.source_text MATCH ?
          AND tm.target_language_id = ?
        ORDER BY bm25(translation_memory_fts) ASC
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

      // Step 4: Sort by similarity (descending), then usage
      matches.sort((a, b) {
        final simCompare = b.similarity.compareTo(a.similarity);
        if (simCompare != 0) return simCompare;

        return b.entry.usageCount.compareTo(a.entry.usageCount);
      });

      // Return top 10 matches
      return matches.take(10).map((m) => m.entry).toList();
    });
  }

  /// Search translation memory entries using FTS5 full-text search.
  ///
  /// This method provides fast, indexed search across source and/or target text
  /// using SQLite FTS5. Performance is O(log n) instead of O(n) for in-memory search.
  ///
  /// [searchText] - Text to search for
  /// [searchScope] - Where to search: 'source', 'target', or 'both'
  /// [targetLanguageId] - Optional target language filter
  /// [limit] - Maximum number of results (default: 50)
  ///
  /// Returns [Ok] with list of matching entries ordered by BM25 rank,
  /// [Err] with exception on failure.
  Future<Result<List<TranslationMemoryEntry>, TWMTDatabaseException>>
      searchFts5({
    required String searchText,
    required String searchScope,
    String? targetLanguageId,
    int limit = 50,
  }) async {
    return executeQuery(() async {
      // Build FTS5 query from search text
      final ftsQuery = _buildFts5SearchQuery(searchText);

      if (ftsQuery.isEmpty) {
        return <TranslationMemoryEntry>[];
      }

      // Build the FTS5 MATCH clause based on search scope.
      //
      // The OR expression MUST be parenthesized: in FTS5 syntax a column
      // filter ('col:' or '{col1 col2}:') binds only to the immediately
      // following phrase, so 'source_text:"a"* OR "b"*' would match the
      // second term against ALL columns and leak results from the other
      // column. 'source_text : ("a"* OR "b"*)' scopes every term.
      // The tokenizer strips '(' and ')' from user input, so the query
      // cannot break out of the group.
      String ftsMatchClause;
      switch (searchScope) {
        case 'source':
          ftsMatchClause = 'source_text : ($ftsQuery)';
          break;
        case 'target':
          ftsMatchClause = 'translated_text : ($ftsQuery)';
          break;
        case 'both':
        default:
          // Search in both columns
          ftsMatchClause = '{source_text translated_text} : ($ftsQuery)';
          break;
      }

      // Build the full query with optional language filter
      String sql;
      List<dynamic> args;

      if (targetLanguageId != null) {
        sql = '''
          SELECT tm.*
          FROM $tableName tm
          INNER JOIN translation_memory_fts fts ON fts.rowid = tm.rowid
          WHERE translation_memory_fts MATCH ?
            AND tm.target_language_id = ?
          ORDER BY bm25(translation_memory_fts)
          LIMIT ?
        ''';
        args = [ftsMatchClause, targetLanguageId, limit];
      } else {
        sql = '''
          SELECT tm.*
          FROM $tableName tm
          INNER JOIN translation_memory_fts fts ON fts.rowid = tm.rowid
          WHERE translation_memory_fts MATCH ?
          ORDER BY bm25(translation_memory_fts)
          LIMIT ?
        ''';
        args = [ftsMatchClause, limit];
      }

      final maps = await database.rawQuery(sql, args);
      return maps.map((map) => fromMap(map)).toList();
    });
  }

  /// Tokenize text for use in an FTS5 MATCH expression.
  ///
  /// Strips FTS5 special characters (" * ( ) :), lowercases, splits on
  /// whitespace and drops tokens shorter than [minWordLength]. The returned
  /// tokens are intended to be wrapped in double quotes (FTS5 strings), so
  /// remaining punctuation (periods, apostrophes, hyphens) is safe: FTS5
  /// tokenizes quoted strings into phrases instead of failing to parse them
  /// as barewords.
  List<String> _tokenizeForFts5(String text, {required int minWordLength}) {
    final sanitized = text
        .replaceAll('"', ' ')
        .replaceAll('*', ' ')
        .replaceAll('(', ' ')
        .replaceAll(')', ' ')
        .replaceAll(':', ' ');

    final words = sanitized
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();

    final significant =
        words.where((word) => word.length >= minWordLength).toList();
    if (significant.isNotEmpty) {
      return significant;
    }

    // Short inputs ("No", "HP", single CJK characters) yield no token that
    // passes the length filter but are still valid searches: fall back to the
    // whole sanitized input as one phrase token, which callers quote — safe
    // for FTS5 regardless of remaining punctuation.
    final phrase = words.join(' ').trim();
    return phrase.isEmpty ? const [] : [phrase];
  }

  /// Build FTS5 query from source text for fuzzy candidate retrieval.
  ///
  /// Extracts significant words and builds an FTS5 MATCH query of quoted
  /// tokens joined with OR. Each token is wrapped in double quotes so that
  /// punctuation in ordinary game text ('attack.', "don't", 'well-trained')
  /// cannot produce an FTS5 syntax error.
  ///
  /// Returns an empty string when the input yields no usable tokens;
  /// callers must short-circuit instead of passing it to MATCH.
  String _buildFts5Query(String text) {
    final words = _tokenizeForFts5(text, minWordLength: 3)
        .take(5) // Limit to 5 most significant words
        .toList();

    if (words.isEmpty) {
      return '';
    }

    // Build OR query: "word1" OR "word2" OR "word3"
    return words.map((w) => '"$w"').join(' OR ');
  }

  /// Build FTS5 search query from user input text.
  ///
  /// Tokenizes input, filters short words, and escapes special characters.
  /// Uses prefix matching (*) for partial word matching.
  String _buildFts5SearchQuery(String text) {
    final words = _tokenizeForFts5(text, minWordLength: 2);

    if (words.isEmpty) {
      // No valid words: return empty so callers short-circuit to no results.
      return '';
    }

    // Build query with prefix matching for better partial matches
    // Use OR for flexibility - matches any of the words
    return words.map((w) => '"$w"*').join(' OR ');
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
}
