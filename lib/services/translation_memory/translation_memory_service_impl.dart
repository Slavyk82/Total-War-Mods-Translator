import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
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
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Translation Memory Service
///
/// This service manages translation memory operations including:
/// - Adding translations with deduplication
/// - Exact and fuzzy match lookup (delegated to TmMatchingService)
/// - TMX import/export (delegated to TmImportExportService)
/// - Statistics and maintenance (delegated to TmStatisticsService)
/// - Search and retrieval (delegated to TmSearchService)
/// - Usage tracking
///
/// Service responsibilities:
/// - Coordinate between repository and delegated services
/// - Handle CRUD operations for TM entries
/// - Manage entry validation
class TranslationMemoryServiceImpl implements ITranslationMemoryService {
  final TranslationMemoryRepository _repository;
  final LanguageRepository _languageRepository;
  final TextNormalizer _normalizer;
  final LoggingService _logger;

  // Cache for language code -> ID mapping
  final Map<String, String> _languageCodeToId = {};

  // Delegated services
  final TmMatchingService _matchingService;
  final TmImportExportService _importExportService;
  final TmStatisticsService _statisticsService;
  final TmSearchService _searchService;

  TranslationMemoryServiceImpl({
    required TranslationMemoryRepository repository,
    required LanguageRepository languageRepository,
    required TextNormalizer normalizer,
    required SimilarityCalculator similarityCalculator,
    required TmCache cache,
    TmxService? tmxService,
    LoggingService? logger,
  })  : _repository = repository,
        _languageRepository = languageRepository,
        _normalizer = normalizer,
        _logger = logger ?? LoggingService.instance,
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
        );

  /// Resolve language code to database ID
  /// Caches results for performance
  Future<String?> _resolveLanguageId(String languageCode) async {
    // Check cache first
    if (_languageCodeToId.containsKey(languageCode)) {
      return _languageCodeToId[languageCode];
    }

    // Look up from database
    final result = await _languageRepository.getByCode(languageCode);
    if (result.isOk) {
      final languageId = result.unwrap().id;
      _languageCodeToId[languageCode] = languageId;
      return languageId;
    }

    _logger.warning('Language not found for code', {'code': languageCode});
    return null;
  }

  // ========== CRUD OPERATIONS ==========

  @override
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
    String? category,
  }) async {
    try {
      // Validate input
      if (sourceText.trim().isEmpty) {
        return Err(
          TmAddException('Source text cannot be empty', sourceText: sourceText),
        );
      }

      if (targetText.trim().isEmpty) {
        return Err(
          TmAddException('Target text cannot be empty', sourceText: sourceText),
        );
      }

      // Calculate source hash using SHA256 for collision resistance
      final normalized = _normalizer.normalize(sourceText);
      final sourceHash = sha256.convert(utf8.encode(normalized)).toString();

      // Resolve language codes to database IDs
      final sourceLanguageId = await _resolveLanguageId(sourceLanguageCode);
      final targetLanguageId = await _resolveLanguageId(targetLanguageCode);

      if (sourceLanguageId == null || targetLanguageId == null) {
        return Err(
          TmAddException(
            'Could not resolve language IDs for codes: $sourceLanguageCode, $targetLanguageCode',
            sourceText: sourceText,
          ),
        );
      }

      // Check for existing entry (deduplication)
      final existingResult = await _repository.findBySourceHash(
        sourceHash,
        targetLanguageId,
      );

      if (existingResult.isOk) {
        return _updateExistingEntry(
          existingResult.value,
          sourceText,
          targetText,
          targetLanguageId,
          sourceHash,
        );
      }

      // Create new entry
      return _createNewEntry(
        sourceText,
        targetText,
        sourceLanguageId,
        targetLanguageId,
        sourceHash,
      );
    } catch (e, stackTrace) {
      return Err(
        TmAddException(
          'Unexpected error adding translation: ${e.toString()}',
          sourceText: sourceText,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<TranslationMemoryEntry, TmAddException>> _updateExistingEntry(
    TranslationMemoryEntry existing,
    String sourceText,
    String targetText,
    String targetLanguageId,
    String sourceHash,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final updatedEntry = TranslationMemoryEntry(
      id: existing.id,
      sourceText: sourceText,
      translatedText: targetText,
      sourceLanguageId: existing.sourceLanguageId,
      targetLanguageId: targetLanguageId,
      sourceHash: sourceHash,
      usageCount: existing.usageCount + 1,
      createdAt: existing.createdAt,
      lastUsedAt: now,
      updatedAt: now,
    );

    final updateResult = await _repository.update(updatedEntry);

    if (updateResult.isErr) {
      return Err(
        TmAddException(
          'Failed to update existing entry: ${updateResult.error}',
          sourceText: sourceText,
        ),
      );
    }

    _logger.debug('Updated existing TM entry', {'entryId': existing.id});
    return Ok(updateResult.value);
  }

  Future<Result<TranslationMemoryEntry, TmAddException>> _createNewEntry(
    String sourceText,
    String targetText,
    String sourceLanguageId,
    String targetLanguageId,
    String sourceHash,
  ) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final entry = TranslationMemoryEntry(
      id: const Uuid().v4(),
      sourceText: sourceText,
      translatedText: targetText,
      sourceLanguageId: sourceLanguageId,
      targetLanguageId: targetLanguageId,
      sourceHash: sourceHash,
      usageCount: 0,
      createdAt: now,
      lastUsedAt: now,
      updatedAt: now,
    );

    final result = await _repository.insert(entry);

    if (result.isErr) {
      return Err(
        TmAddException(
          'Failed to create entry: ${result.error}',
          sourceText: sourceText,
        ),
      );
    }

    return Ok(result.value);
  }

  @override
  Future<Result<int, TmAddException>> addTranslationsBatch({
    required List<({String sourceText, String targetText})> translations,
    String sourceLanguageCode = 'en',
    required String targetLanguageCode,
  }) async {
    if (translations.isEmpty) {
      return const Ok(0);
    }

    try {
      // Resolve language codes to database IDs
      final sourceLanguageId = await _resolveLanguageId(sourceLanguageCode);
      final targetLanguageId = await _resolveLanguageId(targetLanguageCode);

      if (sourceLanguageId == null || targetLanguageId == null) {
        return Err(
          TmAddException(
            'Could not resolve language IDs for codes: $sourceLanguageCode, $targetLanguageCode',
            sourceText: 'batch',
          ),
        );
      }

      // Build list of TM entries
      final entries = _buildBatchEntries(
        translations,
        sourceLanguageId,
        targetLanguageId,
      );

      if (entries.isEmpty) {
        return const Ok(0);
      }

      // Use batch upsert
      final result = await _repository.upsertBatch(entries);

      if (result.isErr) {
        return Err(
          TmAddException(
            'Failed to batch add translations: ${result.error}',
            sourceText: 'batch',
          ),
        );
      }

      _logger.debug(
        'Batch added TM entries',
        {'count': result.value, 'targetLanguage': targetLanguageCode},
      );

      return Ok(result.value);
    } catch (e, stackTrace) {
      return Err(
        TmAddException(
          'Unexpected error in batch add: ${e.toString()}',
          sourceText: 'batch',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  List<TranslationMemoryEntry> _buildBatchEntries(
    List<({String sourceText, String targetText})> translations,
    String sourceLanguageId,
    String targetLanguageId,
  ) {
    final entries = <TranslationMemoryEntry>[];
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    for (final t in translations) {
      // Skip empty translations
      if (t.sourceText.trim().isEmpty || t.targetText.trim().isEmpty) {
        continue;
      }

      // Calculate source hash using SHA256 for collision resistance
      final normalized = _normalizer.normalize(t.sourceText);
      final sourceHash = sha256.convert(utf8.encode(normalized)).toString();

      entries.add(TranslationMemoryEntry(
        id: const Uuid().v4(),
        sourceText: t.sourceText,
        translatedText: t.targetText,
        sourceLanguageId: sourceLanguageId,
        targetLanguageId: targetLanguageId,
        sourceHash: sourceHash,
        usageCount: 0,
        createdAt: now,
        lastUsedAt: now,
        updatedAt: now,
      ));
    }

    return entries;
  }

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({required String entryId}) async {
    try {
      _logger.debug('incrementUsageCount called', {'entryId': entryId});

      // Get current entry
      final getResult = await _repository.getById(entryId);

      if (getResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to get entry: ${getResult.error}',
            error: getResult.error,
          ),
        );
      }

      final entry = getResult.value;

      // Update entry with incremented usage count
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final updatedEntry = TranslationMemoryEntry(
        id: entry.id,
        sourceText: entry.sourceText,
        translatedText: entry.translatedText,
        sourceLanguageId: entry.sourceLanguageId,
        targetLanguageId: entry.targetLanguageId,
        sourceHash: entry.sourceHash,
        usageCount: entry.usageCount + 1,
        createdAt: entry.createdAt,
        lastUsedAt: now,
        updatedAt: now,
      );

      final updateResult = await _repository.update(updatedEntry);

      if (updateResult.isErr) {
        _logger.error('incrementUsageCount failed', {
          'entryId': entryId,
          'error': updateResult.error,
        });
        return Err(
          TmServiceException(
            'Failed to update usage count: ${updateResult.error}',
            error: updateResult.error,
          ),
        );
      }

      _logger.debug('incrementUsageCount success', {
        'entryId': entryId,
        'oldCount': entry.usageCount,
        'newCount': updatedEntry.usageCount,
      });
      return Ok(updateResult.value);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error incrementing usage count: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<void, TmServiceException>> deleteEntry({
    required String entryId,
  }) async {
    try {
      final deleteResult = await _repository.delete(entryId);

      if (deleteResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to delete entry: ${deleteResult.error}',
            error: deleteResult.error,
          ),
        );
      }

      return Ok(null);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error deleting entry: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ========== SEARCH OPERATIONS (Delegated) ==========

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) => _searchService.getEntries(
        targetLanguageCode: targetLanguageCode, limit: limit,
        offset: offset, orderBy: orderBy);

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
  }) => _searchService.searchEntries(
        searchText: searchText, searchIn: searchIn,
        targetLanguageCode: targetLanguageCode, limit: limit);

  // ========== MATCHING OPERATIONS (Delegated) ==========

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

  // ========== IMPORT/EXPORT OPERATIONS (Delegated) ==========

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

  // ========== STATISTICS AND MAINTENANCE (Delegated) ==========

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
}
