import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';
import 'package:twmt/services/translation_memory/tm_matching_service.dart';
import 'package:twmt/services/translation_memory/tm_import_export_service.dart';
import 'package:twmt/services/translation_memory/tm_statistics_service.dart';
import 'package:twmt/services/translation_memory/tm_search_service.dart';
import 'package:twmt/services/translation_memory/tm_crud_service.dart';
import 'package:twmt/services/translation_memory/tm_maintenance_service.dart';
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Translation Memory Service
///
/// This service acts as a facade that coordinates between specialized services:
/// - TmCrudService: Adding, updating, and deleting TM entries
/// - TmMatchingService: Exact and fuzzy match lookup
/// - TmSearchService: FTS5 search and filtered retrieval
/// - TmImportExportService: TMX file import/export
/// - TmStatisticsService: Statistics and cache management
/// - TmMaintenanceService: Rebuild and migration operations
///
/// Each delegated service handles a specific responsibility, keeping
/// this facade lean while providing the full ITranslationMemoryService API.
class TranslationMemoryServiceImpl implements ITranslationMemoryService {
  // Delegated services
  final TmCrudService _crudService;
  final TmMatchingService _matchingService;
  final TmImportExportService _importExportService;
  final TmStatisticsService _statisticsService;
  final TmSearchService _searchService;
  final TmMaintenanceService _maintenanceService;

  TranslationMemoryServiceImpl({
    required TranslationMemoryRepository repository,
    required LanguageRepository languageRepository,
    required TextNormalizer normalizer,
    required SimilarityCalculator similarityCalculator,
    required TmCache cache,
    TmxService? tmxService,
    LoggingService? logger,
  })  : _crudService = TmCrudService(
          repository: repository,
          languageRepository: languageRepository,
          normalizer: normalizer,
          logger: logger,
        ),
        _matchingService = TmMatchingService(
          repository: repository,
          languageRepository: languageRepository,
          normalizer: normalizer,
          similarityCalculator: similarityCalculator,
          cache: cache,
        ),
        _importExportService = TmImportExportService(
          repository: repository,
          tmxService: tmxService ??
              TmxService(
                repository: repository,
                normalizer: normalizer,
                logger: logger,
              ),
          logger: logger ?? LoggingService.instance,
        ),
        _statisticsService = TmStatisticsService(
          repository: repository,
          languageRepository: languageRepository,
          cache: cache,
          logger: logger ?? LoggingService.instance,
        ),
        _searchService = TmSearchService(
          repository: repository,
          logger: logger ?? LoggingService.instance,
        ),
        _maintenanceService = TmMaintenanceService(
          repository: repository,
          crudService: TmCrudService(
            repository: repository,
            languageRepository: languageRepository,
            normalizer: normalizer,
            logger: logger,
          ),
          normalizer: normalizer,
          logger: logger ?? LoggingService.instance,
        );

  // ========== CRUD OPERATIONS (Delegated to TmCrudService) ==========

  @override
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  }) async {
    final result = await _crudService.addTranslation(
      sourceText: sourceText,
      targetText: targetText,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
      category: category,
    );

    // Clear cache after add to ensure new/updated entry is discoverable
    if (result.isOk) {
      await clearCache();
    }

    return result;
  }

  @override
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  }) async {
    final result = await _crudService.addTranslationsBatch(
      translations: translations,
      sourceLanguageCode: sourceLanguageCode,
      targetLanguageCode: targetLanguageCode,
    );

    // Clear cache after batch add to ensure new entries are discoverable
    if (result.isOk) {
      await clearCache();
    }

    return result;
  }

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({required String entryId}) =>
          _crudService.incrementUsageCount(entryId: entryId);

  @override
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) =>
      _crudService.deleteEntry(entryId: entryId);

  // ========== SEARCH OPERATIONS (Delegated to TmSearchService) ==========

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) =>
      _searchService.getEntries(
        targetLanguageCode: targetLanguageCode,
        limit: limit,
        offset: offset,
        orderBy: orderBy,
      );

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
  }) =>
          _searchService.searchEntries(
            searchText: searchText,
            searchIn: searchIn,
            targetLanguageCode: targetLanguageCode,
            limit: limit,
          );

  // ========== MATCHING OPERATIONS (Delegated to TmMatchingService) ==========

  @override
  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
  }) =>
      _matchingService.findExactMatch(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
      );

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    int maxResults = AppConstants.maxTmFuzzyResults,
    String? category,
  }) =>
      _matchingService.findFuzzyMatches(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        minSimilarity: minSimilarity,
        maxResults: maxResults,
        category: category,
      );

  @override
  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    String? category,
  }) =>
      _matchingService.findBestMatch(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        minSimilarity: minSimilarity,
        category: category,
      );

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatchesIsolate({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    int maxResults = AppConstants.maxTmFuzzyResults,
    String? category,
  }) =>
      _matchingService.findFuzzyMatchesIsolate(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        minSimilarity: minSimilarity,
        maxResults: maxResults,
        category: category,
      );

  // ========== IMPORT/EXPORT OPERATIONS (Delegated to TmImportExportService) ==========

  @override
  Future<Result<int, TmImportException>> importFromTmx({
    required String filePath,
    bool overwriteExisting = false,
    void Function(int processed, int total)? onProgress,
  }) async {
    final result = await _importExportService.importFromTmx(
      filePath: filePath,
      overwriteExisting: overwriteExisting,
      onProgress: onProgress,
    );

    // Clear cache after import to ensure fresh data
    if (result.isOk) {
      await clearCache();
    }

    return result;
  }

  @override
  Future<Result<int, TmExportException>> exportToTmx({
    required String outputPath,
    String? sourceLanguageCode,
    String? targetLanguageCode,
  }) =>
      _importExportService.exportToTmx(
        outputPath: outputPath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
      );

  // ========== STATISTICS AND CACHE (Delegated to TmStatisticsService) ==========

  @override
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = AppConstants.unusedTmCleanupDays,
  }) =>
      _statisticsService.cleanupUnusedEntries(unusedDays: unusedDays);

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
  }) =>
      _statisticsService.getStatistics(targetLanguageCode: targetLanguageCode);

  @override
  Future<void> clearCache() async {
    _statisticsService.clearCache();
  }

  @override
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = AppConstants.maxTmCacheEntries,
  }) =>
      _statisticsService.rebuildCache(maxEntries: maxEntries);

  // ========== MAINTENANCE OPERATIONS (Delegated to TmMaintenanceService) ==========

  @override
  Future<Result<({int added, int existing}), TmServiceException>>
      rebuildFromTranslations({
    String? projectId,
    void Function(int processed, int total, int added)? onProgress,
  }) async {
    final result = await _maintenanceService.rebuildFromTranslations(
      projectId: projectId,
      onProgress: onProgress,
    );

    // Clear cache after rebuild
    if (result.isOk) {
      await clearCache();
    }

    return result;
  }

  @override
  Future<Result<int, TmServiceException>> migrateLegacyHashes({
    void Function(int processed, int total)? onProgress,
  }) async {
    final result = await _maintenanceService.migrateLegacyHashes(
      onProgress: onProgress,
    );

    // Clear cache after migration
    if (result.isOk) {
      await clearCache();
    }

    return result;
  }
}
