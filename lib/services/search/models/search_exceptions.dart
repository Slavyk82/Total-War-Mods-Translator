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

/// Saved search not found
class SavedSearchNotFoundException extends SearchServiceException {
  SavedSearchNotFoundException(super.message, {String? searchId})
      : super(
          code: 'SAVED_SEARCH_NOT_FOUND',
          details: {'search_id': searchId},
        );
}

/// Saved search already exists with same name
class DuplicateSavedSearchException extends SearchServiceException {
  DuplicateSavedSearchException(super.message, {String? name})
      : super(
          code: 'DUPLICATE_SAVED_SEARCH',
          details: {'name': name},
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

/// Regular expression is invalid
class InvalidRegexException extends SearchServiceException {
  InvalidRegexException(super.message, {String? pattern, String? error})
      : super(
          code: 'INVALID_REGEX',
          details: {'pattern': pattern, 'error': error},
        );
}

/// Search history limit exceeded
class SearchHistoryLimitException extends SearchServiceException {
  SearchHistoryLimitException(super.message, {int? maxHistory})
      : super(
          code: 'SEARCH_HISTORY_LIMIT',
          details: {'max_history': maxHistory},
        );
}
