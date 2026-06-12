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
}
