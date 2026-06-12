import '../../../models/common/service_exception.dart';

/// Base exception for search service errors
class SearchServiceException extends ServiceException {
  const SearchServiceException(super.message, {super.code, super.details});
}

/// Query is invalid or malformed
class InvalidSearchQueryException extends SearchServiceException {
  InvalidSearchQueryException(super.message, {String? query})
      : super(
          code: 'INVALID_QUERY',
          details: {'query': query},
        );
}

/// FTS5 query syntax error
class FtsQuerySyntaxException extends SearchServiceException {
  FtsQuerySyntaxException(super.message, {String? query, String? error})
      : super(
          code: 'FTS_SYNTAX_ERROR',
          details: {'query': query, 'error': error},
        );
}

/// Search operation timed out
class SearchTimeoutException extends SearchServiceException {
  SearchTimeoutException(super.message, {Duration? timeout})
      : super(
          code: 'SEARCH_TIMEOUT',
          details: {'timeout_ms': timeout?.inMilliseconds},
        );
}

/// Search index not initialized
class SearchIndexNotInitializedException extends SearchServiceException {
  SearchIndexNotInitializedException(super.message, {String? indexName})
      : super(
          code: 'INDEX_NOT_INITIALIZED',
          details: {'index': indexName},
        );
}

/// Database error during search
class SearchDatabaseException extends SearchServiceException {
  SearchDatabaseException(super.message, {Object? dbError})
      : super(
          code: 'SEARCH_DB_ERROR',
          details: {'db_error': dbError.toString()},
        );
}

/// Too many search results (exceeded limit)
class TooManyResultsException extends SearchServiceException {
  TooManyResultsException(
    super.message, {
    int? resultCount,
    int? maxResults,
  }) : super(
          code: 'TOO_MANY_RESULTS',
          details: {'result_count': resultCount, 'max_results': maxResults},
        );
}
