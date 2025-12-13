import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Translation Memory search service
///
/// Handles:
/// - FTS5 full-text search with fallback
/// - Filtered retrieval of TM entries
/// - In-memory search when FTS5 unavailable
class TmSearchService {
  final TranslationMemoryRepository _repository;
  final LoggingService _logger;

  const TmSearchService({
    required TranslationMemoryRepository repository,
    required LoggingService logger,
  })  : _repository = repository,
        _logger = logger;

  /// Get TM entries with optional filters
  ///
  /// [targetLanguageCode]: Optional target language filter
  /// [limit]: Maximum results
  /// [offset]: Pagination offset
  /// [orderBy]: Sort column and direction (default: 'usage_count DESC')
  ///
  /// Returns paginated list of TM entries
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async {
    try {
      // Convert language code to ID format (e.g., 'fr' -> 'lang_fr')
      final targetLanguageId =
          targetLanguageCode != null ? 'lang_$targetLanguageCode' : null;

      final result = await _repository.getWithFilters(
        targetLanguageId: targetLanguageId,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
      );

      if (result.isErr) {
        return Err(
          TmServiceException(
            'Failed to get entries: ${result.error}',
            error: result.error,
          ),
        );
      }

      return Ok(result.value);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error getting entries: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Search TM entries by text
  ///
  /// Uses FTS5 full-text search for fast results with fallback to in-memory.
  ///
  /// [searchText]: Text to search for
  /// [searchIn]: Where to search (source, target, both)
  /// [targetLanguageCode]: Optional language filter
  /// [limit]: Maximum results
  ///
  /// Returns matching TM entries
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
  }) async {
    try {
      // Validate input
      if (searchText.trim().isEmpty) {
        return const Ok([]);
      }

      // Convert language code to ID format
      final targetLanguageId =
          targetLanguageCode != null ? 'lang_$targetLanguageCode' : null;

      // Convert TmSearchScope enum to string for repository
      final searchScope = switch (searchIn) {
        TmSearchScope.source => 'source',
        TmSearchScope.target => 'target',
        TmSearchScope.both => 'both',
      };

      // Try FTS5 search first (O(log n) performance)
      final ftsResult = await _repository.searchFts5(
        searchText: searchText,
        searchScope: searchScope,
        targetLanguageId: targetLanguageId,
        limit: limit,
      );

      if (ftsResult.isOk) {
        _logger.debug('FTS5 search completed', {
          'query': searchText,
          'scope': searchScope,
          'resultsCount': ftsResult.value.length,
        });
        return Ok(ftsResult.value);
      }

      // FTS5 failed, fall back to in-memory search
      _logger.warning(
        'FTS5 search failed, falling back to in-memory search',
        {'error': ftsResult.error.toString()},
      );

      return _searchEntriesInMemory(
        searchText: searchText,
        searchIn: searchIn,
        targetLanguageId: targetLanguageId,
        limit: limit,
      );
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error searching entries: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Fallback in-memory search when FTS5 is unavailable or fails.
  ///
  /// Performance: O(n) where n = total TM entries.
  /// Use only as fallback when FTS5 search fails.
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      _searchEntriesInMemory({
    required String searchText,
    required TmSearchScope searchIn,
    String? targetLanguageId,
    required int limit,
  }) async {
    try {
      final allResult = await _repository.getAll();

      if (allResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to search entries: ${allResult.error}',
            error: allResult.error,
          ),
        );
      }

      final searchLower = searchText.toLowerCase();
      final filtered = allResult.value.where((entry) {
        // Apply language filter if specified
        if (targetLanguageId != null &&
            entry.targetLanguageId != targetLanguageId) {
          return false;
        }

        final matchSource =
            searchIn == TmSearchScope.source || searchIn == TmSearchScope.both;
        final matchTarget =
            searchIn == TmSearchScope.target || searchIn == TmSearchScope.both;

        return (matchSource &&
                entry.sourceText.toLowerCase().contains(searchLower)) ||
            (matchTarget &&
                entry.translatedText.toLowerCase().contains(searchLower));
      }).take(limit).toList();

      return Ok(filtered);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error in fallback search: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
