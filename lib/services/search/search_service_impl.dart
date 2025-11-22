import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import '../database/database_service.dart';
import '../../config/app_constants.dart';
import '../../models/common/result.dart';
import 'i_search_service.dart';
import 'models/search_result.dart';
import 'models/search_exceptions.dart';
import 'utils/query_builder.dart' as legacy;
import 'utils/fts_query_builder.dart' as sql_builder;
import 'utils/regex_query_builder.dart';
import 'search_history_service.dart';

/// Implementation of search service using FTS5 full-text search
///
/// Provides 100-1000x faster search than LIKE queries by leveraging
/// SQLite FTS5 virtual tables.
class SearchServiceImpl implements ISearchService {
  final SearchHistoryService _historyService;

  SearchServiceImpl({
    DatabaseService? databaseService,
    Uuid? uuid,
    SearchHistoryService? historyService,
  }) : _historyService = historyService ?? SearchHistoryService(uuid: uuid);

  Database get _db => DatabaseService.database;

  @override
  Future<Result<List<SearchResult>, SearchServiceException>>
      searchTranslationUnits(
    String query, {
    SearchFilter? filter,
    int limit = AppConstants.defaultSearchLimit,
    int offset = 0,
  }) async {
    try {
      // Validate query
      if (query.trim().isEmpty) {
        return Err(InvalidSearchQueryException('Query cannot be empty'));
      }

      // Validate and build FTS5 query
      final ftsQuery = legacy.FtsQueryBuilder.buildFtsQuery(query);
      if (!legacy.FtsQueryBuilder.validateFtsQuery(ftsQuery)) {
        return Err(FtsQuerySyntaxException('Invalid FTS5 syntax', query: query));
      }

      // Build SQL query with FTS5 MATCH
      final sql = sql_builder.FtsQueryBuilder.buildTranslationUnitsQuery(
        ftsQuery,
        filter: filter,
        limit: limit,
        offset: offset,
      );

      // Execute search
      final results = await _db.rawQuery(sql);

      // Convert to SearchResult objects
      final searchResults = results.map((row) {
        return SearchResult(
          id: row['id'] as String,
          type: SearchResultType.translationUnit,
          projectId: row['project_id'] as String?,
          projectName: row['project_name'] as String?,
          key: row['key'] as String?,
          sourceText: row['source_text'] as String?,
          matchedField: _detectMatchedField(row),
          highlightedText: row['highlighted'] as String? ?? '',
          relevanceScore: (row['rank'] as num?)?.toDouble() ?? 0.0,
          context: _extractContext(row['source_text'] as String?, query),
          fileName: row['file_name'] as String?,
          createdAt: _parseTimestamp(row['created_at']),
          updatedAt: _parseTimestamp(row['updated_at']),
        );
      }).toList();

      // Add to search history
      await _historyService.addToSearchHistory(query, searchResults.length);

      return Ok(searchResults);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Database error during search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error during search',
          dbError: e));
    }
  }

  @override
  Future<Result<List<SearchResult>, SearchServiceException>>
      searchTranslationVersions(
    String query, {
    SearchFilter? filter,
    int limit = AppConstants.defaultSearchLimit,
    int offset = 0,
  }) async {
    try {
      // Validate query
      if (query.trim().isEmpty) {
        return Err(InvalidSearchQueryException('Query cannot be empty'));
      }

      // Build FTS5 query
      final ftsQuery = legacy.FtsQueryBuilder.buildFtsQuery(query);
      if (!legacy.FtsQueryBuilder.validateFtsQuery(ftsQuery)) {
        return Err(FtsQuerySyntaxException('Invalid FTS5 syntax', query: query));
      }

      // Build SQL query
      final sql = sql_builder.FtsQueryBuilder.buildTranslationVersionsQuery(
        ftsQuery,
        filter: filter,
        limit: limit,
        offset: offset,
      );

      // Execute search
      final results = await _db.rawQuery(sql);

      // Convert to SearchResult objects
      final searchResults = results.map((row) {
        return SearchResult(
          id: row['id'] as String,
          type: SearchResultType.translationVersion,
          projectId: row['project_id'] as String?,
          projectName: row['project_name'] as String?,
          languageCode: row['language_code'] as String?,
          languageName: row['language_name'] as String?,
          key: row['key'] as String?,
          sourceText: row['source_text'] as String?,
          translatedText: row['translated_text'] as String?,
          matchedField: 'translated_text',
          highlightedText: row['highlighted'] as String? ?? '',
          relevanceScore: (row['rank'] as num?)?.toDouble() ?? 0.0,
          context: _extractContext(row['translated_text'] as String?, query),
          status: row['status'] as String?,
          createdAt: _parseTimestamp(row['created_at']),
          updatedAt: _parseTimestamp(row['updated_at']),
        );
      }).toList();

      // Add to search history
      await _historyService.addToSearchHistory(query, searchResults.length);

      return Ok(searchResults);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Database error during search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error during search',
          dbError: e));
    }
  }

  @override
  Future<Result<List<SearchResult>, SearchServiceException>>
      searchTranslationMemory(
    String query, {
    String? sourceLanguage,
    String? targetLanguage,
    int limit = AppConstants.defaultSearchLimit,
    int offset = 0,
  }) async {
    try {
      // Validate query
      if (query.trim().isEmpty) {
        return Err(InvalidSearchQueryException('Query cannot be empty'));
      }

      // Build FTS5 query
      final ftsQuery = legacy.FtsQueryBuilder.buildFtsQuery(query);
      if (!legacy.FtsQueryBuilder.validateFtsQuery(ftsQuery)) {
        return Err(FtsQuerySyntaxException('Invalid FTS5 syntax', query: query));
      }

      // Build SQL query
      final sql = sql_builder.FtsQueryBuilder.buildTranslationMemoryQuery(
        ftsQuery,
        targetLanguage: targetLanguage,
        limit: limit,
        offset: offset,
      );

      // Execute search
      final results = await _db.rawQuery(sql);

      // Convert to SearchResult objects
      final searchResults = results.map((row) {
        return SearchResult(
          id: row['id'] as String,
          type: SearchResultType.translationMemory,
          languageCode: row['target_language'] as String?,
          sourceText: row['source_text'] as String?,
          translatedText: row['target_text'] as String?,
          matchedField: _detectMatchedField(row),
          highlightedText: row['highlighted'] as String? ?? '',
          relevanceScore: (row['rank'] as num?)?.toDouble() ?? 0.0,
          context: _extractContext(row['source_text'] as String?, query),
          createdAt: _parseTimestamp(row['created_at']),
          updatedAt: _parseTimestamp(row['last_used_at']),
        );
      }).toList();

      // Add to search history
      await _historyService.addToSearchHistory(query, searchResults.length);

      return Ok(searchResults);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Database error during search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error during search',
          dbError: e));
    }
  }

  @override
  Future<Result<List<SearchResult>, SearchServiceException>> searchGlossary(
    String query, {
    String? glossaryId,
    String? category,
    int limit = AppConstants.defaultSearchLimit,
    int offset = 0,
  }) async {
    try {
      // Validate query
      if (query.trim().isEmpty) {
        return Err(InvalidSearchQueryException('Query cannot be empty'));
      }

      // Build SQL query (glossary uses simple LIKE for now, can add FTS5 later)
      final sql = sql_builder.FtsQueryBuilder.buildGlossaryQuery(
        query,
        glossaryId: glossaryId,
        category: category,
        limit: limit,
        offset: offset,
      );

      // Execute search
      final results = await _db.rawQuery(sql);

      // Convert to SearchResult objects
      final searchResults = results.map((row) {
        return SearchResult(
          id: row['id'] as String,
          type: SearchResultType.glossaryEntry,
          sourceText: row['term'] as String?,
          translatedText: row['translation'] as String?,
          matchedField: 'term',
          highlightedText: _highlightText(row['term'] as String?, query),
          relevanceScore: 1.0, // No ranking for LIKE queries
          context: row['notes'] as String?,
          category: row['category'] as String?,
          createdAt: _parseTimestamp(row['created_at']),
          updatedAt: _parseTimestamp(row['updated_at']),
        );
      }).toList();

      // Add to search history
      await _historyService.addToSearchHistory(query, searchResults.length);

      return Ok(searchResults);
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Database error during search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error during search',
          dbError: e));
    }
  }

  @override
  Future<Result<List<SearchResult>, SearchServiceException>> searchAll(
    String query, {
    SearchFilter? filter,
    int limit = AppConstants.defaultSearchLimit,
  }) async {
    try {
      // Validate query
      if (query.trim().isEmpty) {
        return Err(InvalidSearchQueryException('Query cannot be empty'));
      }

      // Search in parallel across all sources
      final results = await Future.wait([
        searchTranslationUnits(query, filter: filter, limit: limit ~/ 3),
        searchTranslationVersions(query, filter: filter, limit: limit ~/ 3),
        searchTranslationMemory(query, limit: limit ~/ 3),
      ]);

      // Combine results
      final allResults = <SearchResult>[];
      for (final result in results) {
        if (result is Ok<List<SearchResult>, SearchServiceException>) {
          allResults.addAll(result.value);
        }
      }

      // Sort by relevance score (descending)
      allResults.sort((a, b) => b.relevanceScore.compareTo(a.relevanceScore));

      // Limit total results
      final limitedResults = allResults.take(limit).toList();

      return Ok(limitedResults);
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error during search',
          dbError: e));
    }
  }

  @override
  Future<Result<List<SearchResult>, SearchServiceException>> searchWithRegex(
    String pattern, {
    String searchIn = 'both',
    SearchFilter? filter,
    int limit = AppConstants.defaultSearchLimit,
  }) async {
    try {
      // Validate and escape regex pattern
      final regexPattern = RegexQueryBuilder.validateAndEscapePattern(pattern);

      // Build SQL query with REGEXP
      final sql = RegexQueryBuilder.buildRegexQuery(
        regexPattern,
        searchIn: searchIn,
        filter: filter,
        limit: limit,
      );

      // Execute search
      final results = await _db.rawQuery(sql);

      // Convert to SearchResult objects
      final searchResults = results.map((row) {
        return SearchResult(
          id: row['id'] as String,
          type: SearchResultType.translationUnit,
          projectId: row['project_id'] as String?,
          projectName: row['project_name'] as String?,
          key: row['key'] as String?,
          sourceText: row['source_text'] as String?,
          translatedText: row['translated_text'] as String?,
          matchedField: row['matched_field'] as String? ?? 'source_text',
          highlightedText: row['source_text'] as String? ?? '',
          relevanceScore: 1.0, // No ranking for REGEXP
          createdAt: _parseTimestamp(row['created_at']),
          updatedAt: _parseTimestamp(row['updated_at']),
        );
      }).toList();

      // Add to search history
      await _historyService.addToSearchHistory(
          'REGEX: $pattern', searchResults.length);

      return Ok(searchResults);
    } on ArgumentError catch (e) {
      return Err(InvalidRegexException(e.message, pattern: pattern));
    } on DatabaseException catch (e) {
      return Err(SearchDatabaseException('Database error during regex search',
          dbError: e));
    } catch (e) {
      return Err(SearchDatabaseException('Unexpected error during regex search',
          dbError: e));
    }
  }

  // Delegate history operations to SearchHistoryService

  @override
  Future<Result<List<Map<String, dynamic>>, SearchServiceException>>
      getSearchHistory({int limit = AppConstants.defaultSearchHistoryLimit}) async {
    return _historyService.getSearchHistory(limit: limit);
  }

  @override
  Future<Result<bool, SearchServiceException>> addToSearchHistory(
    String query,
    int resultCount,
  ) async {
    return _historyService.addToSearchHistory(query, resultCount);
  }

  @override
  Future<Result<int, SearchServiceException>> clearSearchHistory() async {
    return _historyService.clearSearchHistory();
  }

  @override
  Future<Result<SavedSearch, SearchServiceException>> saveSearch(
    String name,
    String query, {
    SearchFilter? filter,
  }) async {
    return _historyService.saveSearch(name, query, filter: filter);
  }

  @override
  Future<Result<List<SavedSearch>, SearchServiceException>>
      getSavedSearches() async {
    return _historyService.getSavedSearches();
  }

  @override
  Future<Result<SavedSearch, SearchServiceException>> getSavedSearch(
      String id) async {
    return _historyService.getSavedSearch(id);
  }

  @override
  Future<Result<SavedSearch, SearchServiceException>> updateSavedSearch(
    String id, {
    String? name,
    String? query,
    SearchFilter? filter,
  }) async {
    return _historyService.updateSavedSearch(
      id,
      name: name,
      query: query,
      filter: filter,
    );
  }

  @override
  Future<Result<bool, SearchServiceException>> deleteSavedSearch(
      String id) async {
    return _historyService.deleteSavedSearch(id);
  }

  @override
  Future<Result<bool, SearchServiceException>> incrementSavedSearchUsage(
      String id) async {
    return _historyService.incrementSavedSearchUsage(id);
  }

  @override
  Future<Result<bool, SearchServiceException>> validateFtsQuery(
      String query) async {
    try {
      final isValid = legacy.FtsQueryBuilder.validateFtsQuery(query);
      return Ok(isValid);
    } on ArgumentError catch (e) {
      return Err(FtsQuerySyntaxException(e.message, query: query));
    } catch (e) {
      return Err(InvalidSearchQueryException('Unexpected validation error',
          query: query));
    }
  }

  @override
  Future<Result<Map<String, dynamic>, SearchServiceException>>
      getSearchStatistics() async {
    return _historyService.getSearchStatistics();
  }

  // Helper methods

  /// Detect which field matched in the search result
  String _detectMatchedField(Map<String, dynamic> row) {
    if (row['key'] != null) return 'key';
    if (row['source_text'] != null) return 'source_text';
    if (row['translated_text'] != null) return 'translated_text';
    return 'unknown';
  }

  /// Extract context around the matched query in text
  ///
  /// Parameters:
  /// - [text]: Full text to extract context from
  /// - [query]: Search query to locate
  ///
  /// Returns: Context snippet with ellipsis
  String _extractContext(String? text, String query) {
    if (text == null || text.isEmpty) return '';

    // Find query position in text (case-insensitive)
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    if (index == -1) {
      return text.substring(0, AppConstants.searchContextLength.clamp(0, text.length));
    }

    // Extract context around match
    final start = (index - AppConstants.searchContextLength ~/ 2).clamp(0, text.length);
    final end =
        (index + query.length + AppConstants.searchContextLength ~/ 2).clamp(0, text.length);

    var context = text.substring(start, end);
    if (start > 0) context = '...$context';
    if (end < text.length) context = '$context...';

    return context;
  }

  /// Highlight query text with <mark> tags
  ///
  /// Parameters:
  /// - [text]: Text to highlight
  /// - [query]: Query to highlight
  ///
  /// Returns: Text with highlighted query wrapped in <mark> tags
  String _highlightText(String? text, String query) {
    if (text == null || text.isEmpty) return '';

    // Simple highlighting (replace with <mark> tags)
    final regex = RegExp(RegExp.escape(query), caseSensitive: false);
    return text.replaceAllMapped(
      regex,
      (match) => '<mark>${match.group(0)}</mark>',
    );
  }

  /// Parse timestamp from database
  ///
  /// Parameters:
  /// - [timestamp]: Timestamp value (int or null)
  ///
  /// Returns: DateTime object or null
  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    if (timestamp is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestamp);
    }
    return null;
  }
}
