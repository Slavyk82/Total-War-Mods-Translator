import '../../models/common/result.dart';
import 'models/search_result.dart';
import 'models/search_exceptions.dart';

/// Search service interface for FTS5 full-text search operations
///
/// Provides 100-1000x faster search than LIKE queries using SQLite FTS5.
/// Supports advanced search operators, filters, highlighting, and ranking.
abstract class ISearchService {
  /// Search across translation units (source text and keys)
  ///
  /// Uses FTS5 virtual table `translation_units_fts` for fast full-text search.
  ///
  /// Parameters:
  /// - [query]: Search query (supports FTS5 operators: AND, OR, NOT, phrase, prefix)
  /// - [filter]: Optional filters (project, language, status, date range)
  /// - [limit]: Maximum number of results (default: 100, max: 1000)
  /// - [offset]: Offset for pagination (default: 0)
  ///
  /// Returns:
  /// - [Ok]: List of search results ranked by relevance
  /// - [Err]: [InvalidSearchQueryException], [FtsQuerySyntaxException], [SearchDatabaseException]
  ///
  /// Example:
  /// ```dart
  /// // Simple search
  /// final result = await service.searchTranslationUnits('cavalry unit');
  ///
  /// // Search with operators
  /// final result = await service.searchTranslationUnits('"cavalry unit" OR infantry');
  ///
  /// // Search with filter
  /// final result = await service.searchTranslationUnits(
  ///   'cavalry',
  ///   filter: SearchFilter(projectIds: ['proj123']),
  /// );
  /// ```
  Future<Result<List<SearchResult>, SearchServiceException>>
      searchTranslationUnits(
    String query, {
    SearchFilter? filter,
    int limit = 100,
    int offset = 0,
  });

  /// Search across translation versions (translated text)
  ///
  /// Uses FTS5 virtual table `translation_versions_fts` for fast full-text search.
  ///
  /// Parameters:
  /// - [query]: Search query
  /// - [filter]: Optional filters (project, language, status, date range)
  /// - [limit]: Maximum number of results (default: 100, max: 1000)
  /// - [offset]: Offset for pagination (default: 0)
  ///
  /// Returns:
  /// - [Ok]: List of search results ranked by relevance
  /// - [Err]: [InvalidSearchQueryException], [FtsQuerySyntaxException], [SearchDatabaseException]
  Future<Result<List<SearchResult>, SearchServiceException>>
      searchTranslationVersions(
    String query, {
    SearchFilter? filter,
    int limit = 100,
    int offset = 0,
  });

  /// Search across translation memory entries
  ///
  /// Uses FTS5 virtual table `translation_memory_fts` for fast full-text search.
  ///
  /// Parameters:
  /// - [query]: Search query
  /// - [sourceLanguage]: Source language code (optional)
  /// - [targetLanguage]: Target language code (optional)
  /// - [limit]: Maximum number of results (default: 100, max: 1000)
  /// - [offset]: Offset for pagination (default: 0)
  ///
  /// Returns:
  /// - [Ok]: List of TM search results ranked by relevance
  /// - [Err]: [InvalidSearchQueryException], [FtsQuerySyntaxException], [SearchDatabaseException]
  Future<Result<List<SearchResult>, SearchServiceException>>
      searchTranslationMemory(
    String query, {
    String? sourceLanguage,
    String? targetLanguage,
    int limit = 100,
    int offset = 0,
  });

  /// Search across glossary entries
  ///
  /// Searches term, translation, notes, and category fields.
  ///
  /// Parameters:
  /// - [query]: Search query
  /// - [glossaryId]: Filter by glossary ID (optional)
  /// - [category]: Filter by category (optional)
  /// - [limit]: Maximum number of results (default: 100, max: 1000)
  /// - [offset]: Offset for pagination (default: 0)
  ///
  /// Returns:
  /// - [Ok]: List of glossary search results
  /// - [Err]: [InvalidSearchQueryException], [SearchDatabaseException]
  Future<Result<List<SearchResult>, SearchServiceException>> searchGlossary(
    String query, {
    String? glossaryId,
    String? category,
    int limit = 100,
    int offset = 0,
  });

  /// Search across all entities (units, versions, TM, glossary)
  ///
  /// Performs parallel search across all FTS5 tables and combines results.
  ///
  /// Parameters:
  /// - [query]: Search query
  /// - [filter]: Optional filters
  /// - [limit]: Maximum total results (default: 100, max: 1000)
  ///
  /// Returns:
  /// - [Ok]: Combined list of search results ranked by relevance
  /// - [Err]: [InvalidSearchQueryException], [SearchDatabaseException]
  Future<Result<List<SearchResult>, SearchServiceException>> searchAll(
    String query, {
    SearchFilter? filter,
    int limit = 100,
  });

  /// Search using regular expression (slower than FTS5)
  ///
  /// Falls back to REGEXP operator when FTS5 operators are insufficient.
  /// Note: Significantly slower than FTS5 for large datasets.
  ///
  /// Parameters:
  /// - [pattern]: Regular expression pattern
  /// - [searchIn]: Fields to search in ('source', 'target', or 'both')
  /// - [filter]: Optional filters
  /// - [limit]: Maximum number of results (default: 100)
  ///
  /// Returns:
  /// - [Ok]: List of search results
  /// - [Err]: [InvalidRegexException], [SearchDatabaseException]
  Future<Result<List<SearchResult>, SearchServiceException>> searchWithRegex(
    String pattern, {
    String searchIn = 'both',
    SearchFilter? filter,
    int limit = 100,
  });

  /// Get search history (last N searches)
  ///
  /// Returns the most recent search queries executed by the user.
  ///
  /// Parameters:
  /// - [limit]: Maximum number of history entries (default: 50, max: 100)
  ///
  /// Returns:
  /// - [Ok]: List of recent search queries with timestamps
  /// - [Err]: [SearchDatabaseException]
  Future<Result<List<Map<String, dynamic>>, SearchServiceException>>
      getSearchHistory({int limit = 50});

  /// Add query to search history
  ///
  /// Stores the search query for future reference. Automatically called
  /// by search methods.
  ///
  /// Parameters:
  /// - [query]: Search query to save
  /// - [resultCount]: Number of results found
  ///
  /// Returns:
  /// - [Ok]: true if saved successfully
  /// - [Err]: [SearchHistoryLimitException], [SearchDatabaseException]
  Future<Result<bool, SearchServiceException>> addToSearchHistory(
    String query,
    int resultCount,
  );

  /// Clear search history
  ///
  /// Removes all search history entries.
  ///
  /// Returns:
  /// - [Ok]: Number of entries deleted
  /// - [Err]: [SearchDatabaseException]
  Future<Result<int, SearchServiceException>> clearSearchHistory();

  /// Save a search query for later use
  ///
  /// Parameters:
  /// - [name]: Display name for the saved search
  /// - [query]: Search query to save
  /// - [filter]: Optional search filter
  ///
  /// Returns:
  /// - [Ok]: Created SavedSearch object
  /// - [Err]: [DuplicateSavedSearchException], [SearchDatabaseException]
  Future<Result<SavedSearch, SearchServiceException>> saveSearch(
    String name,
    String query, {
    SearchFilter? filter,
  });

  /// Get all saved searches
  ///
  /// Returns:
  /// - [Ok]: List of saved searches ordered by usage count (descending)
  /// - [Err]: [SearchDatabaseException]
  Future<Result<List<SavedSearch>, SearchServiceException>> getSavedSearches();

  /// Get a saved search by ID
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  ///
  /// Returns:
  /// - [Ok]: SavedSearch object
  /// - [Err]: [SavedSearchNotFoundException], [SearchDatabaseException]
  Future<Result<SavedSearch, SearchServiceException>> getSavedSearch(
      String id);

  /// Update a saved search
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  /// - [name]: New name (optional)
  /// - [query]: New query (optional)
  /// - [filter]: New filter (optional)
  ///
  /// Returns:
  /// - [Ok]: Updated SavedSearch object
  /// - [Err]: [SavedSearchNotFoundException], [DuplicateSavedSearchException], [SearchDatabaseException]
  Future<Result<SavedSearch, SearchServiceException>> updateSavedSearch(
    String id, {
    String? name,
    String? query,
    SearchFilter? filter,
  });

  /// Delete a saved search
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  ///
  /// Returns:
  /// - [Ok]: true if deleted successfully
  /// - [Err]: [SavedSearchNotFoundException], [SearchDatabaseException]
  Future<Result<bool, SearchServiceException>> deleteSavedSearch(String id);

  /// Increment usage count for a saved search
  ///
  /// Called automatically when executing a saved search.
  ///
  /// Parameters:
  /// - [id]: Saved search ID
  ///
  /// Returns:
  /// - [Ok]: true if updated successfully
  /// - [Err]: [SavedSearchNotFoundException], [SearchDatabaseException]
  Future<Result<bool, SearchServiceException>> incrementSavedSearchUsage(
      String id);

  /// Validate FTS5 query syntax
  ///
  /// Checks if the query is valid before executing it.
  ///
  /// Parameters:
  /// - [query]: FTS5 query to validate
  ///
  /// Returns:
  /// - [Ok]: true if query is valid
  /// - [Err]: [FtsQuerySyntaxException]
  Future<Result<bool, SearchServiceException>> validateFtsQuery(String query);

  /// Get search statistics
  ///
  /// Returns statistics about search usage and performance.
  ///
  /// Returns:
  /// - [Ok]: Map with statistics (total_searches, avg_results, most_searched_terms, etc.)
  /// - [Err]: [SearchDatabaseException]
  Future<Result<Map<String, dynamic>, SearchServiceException>>
      getSearchStatistics();
}
