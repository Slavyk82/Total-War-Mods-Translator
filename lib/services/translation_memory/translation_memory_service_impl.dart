import 'dart:async';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
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
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Translation Memory Service
///
/// This service manages translation memory operations including:
/// - Adding translations with deduplication
/// - Exact and fuzzy match lookup (delegated to TmMatchingService)
/// - TMX import/export (delegated to TmImportExportService)
/// - Quality scoring and usage tracking
/// - Cache management
///
/// Service responsibilities:
/// - Coordinate between repository, matching, and import/export services
/// - Handle CRUD operations for TM entries
/// - Manage entry validation and quality control
/// - Provide statistics and maintenance operations
class TranslationMemoryServiceImpl implements ITranslationMemoryService {
  final TranslationMemoryRepository _repository;
  final TextNormalizer _normalizer;
  final TmCache _cache;
  final LoggingService _logger;

  // Delegated services
  final TmMatchingService _matchingService;
  final TmImportExportService _importExportService;

  TranslationMemoryServiceImpl({
    required TranslationMemoryRepository repository,
    required TextNormalizer normalizer,
    required SimilarityCalculator similarityCalculator,
    required TmCache cache,
    TmxService? tmxService,
    LoggingService? logger,
  })  : _repository = repository,
        _normalizer = normalizer,
        _cache = cache,
        _logger = logger ?? LoggingService.instance,
        _matchingService = TmMatchingService(
          repository: repository,
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
        );

  // ========== CRUD OPERATIONS ==========

  @override
  Future<Result<TranslationMemoryEntry, TmAddException>> addTranslation({
    required String sourceText,
    required String targetText,
    required String targetLanguageCode,
    String? gameContext,
    String? category,
    double quality = AppConstants.defaultTmQuality,
  }) async {
    try {
      // Validate input
      if (sourceText.trim().isEmpty) {
        return Err(
          TmAddException(
            'Source text cannot be empty',
            sourceText: sourceText,
          ),
        );
      }

      if (targetText.trim().isEmpty) {
        return Err(
          TmAddException(
            'Target text cannot be empty',
            sourceText: sourceText,
          ),
        );
      }

      if (quality < AppConstants.minQualityClamp || quality > AppConstants.maxQualityClamp) {
        return Err(
          TmAddException(
            'Quality must be between ${AppConstants.minQualityClamp} and ${AppConstants.maxQualityClamp}',
            sourceText: sourceText,
          ),
        );
      }

      // Calculate source hash (using normalized text as deterministic hash)
      final normalized = _normalizer.normalize(sourceText);
      final sourceHash = normalized.hashCode.toString();

      // Check for existing entry (deduplication)
      final existingResult = await _repository.findBySourceHash(
        sourceHash,
        targetLanguageCode,
      );

      if (existingResult.isOk) {
        // Entry exists, update usage and quality if needed
        final existing = existingResult.value;
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

        // Use higher quality between existing and new
        final updatedQuality = existing.qualityScore != null
            ? (existing.qualityScore! > quality
                ? existing.qualityScore!
                : quality)
            : quality;

        final updatedEntry = TranslationMemoryEntry(
          id: existing.id,
          sourceText: sourceText,
          translatedText: targetText,
          targetLanguageId: targetLanguageCode,
          sourceHash: sourceHash,
          qualityScore: updatedQuality,
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

        _logger.debug(
          'Updated existing TM entry',
          {'entryId': existing.id, 'newQuality': updatedQuality},
        );

        return Ok(updateResult.value);
      }

      // Create new entry
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final entry = TranslationMemoryEntry(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        sourceText: sourceText,
        translatedText: targetText,
        targetLanguageId: targetLanguageCode,
        sourceHash: sourceHash,
        qualityScore: quality,
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

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({
    required String entryId,
  }) async {
    try {
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
        targetLanguageId: entry.targetLanguageId,
        sourceHash: entry.sourceHash,
        qualityScore: entry.qualityScore,
        usageCount: entry.usageCount + 1,
        createdAt: entry.createdAt,
        lastUsedAt: now,
        updatedAt: now,
      );

      final updateResult = await _repository.update(updatedEntry);

      if (updateResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to update usage count: ${updateResult.error}',
            error: updateResult.error,
          ),
        );
      }

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
  Future<Result<TranslationMemoryEntry, TmServiceException>> updateQuality({
    required String entryId,
    required double newQuality,
  }) async {
    try {
      // Validate quality
      if (newQuality < AppConstants.minQualityClamp || newQuality > AppConstants.maxQualityClamp) {
        return Err(
          TmServiceException(
            'Quality must be between ${AppConstants.minQualityClamp} and ${AppConstants.maxQualityClamp}',
          ),
        );
      }

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

      // Update entry with new quality
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final updatedEntry = TranslationMemoryEntry(
        id: entry.id,
        sourceText: entry.sourceText,
        translatedText: entry.translatedText,
        targetLanguageId: entry.targetLanguageId,
        sourceHash: entry.sourceHash,
        qualityScore: newQuality,
        usageCount: entry.usageCount,
        createdAt: entry.createdAt,
        lastUsedAt: entry.lastUsedAt,
        updatedAt: now,
      );

      final updateResult = await _repository.update(updatedEntry);

      if (updateResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to update quality: ${updateResult.error}',
            error: updateResult.error,
          ),
        );
      }

      return Ok(updateResult.value);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error updating quality: ${e.toString()}',
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

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    String? gameContext,
    int limit = AppConstants.defaultTmPageSize,
    int offset = 0,
  }) async {
    try {
      final result = await _repository.getWithFilters(
        targetLanguageId: targetLanguageCode,
        limit: limit,
        offset: offset,
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

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>>
      searchEntries({
    required String searchText,
    TmSearchScope searchIn = TmSearchScope.both,
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
  }) async {
    // TODO: Implement when repository supports FTS5 full-text search
    // For now, do a simple in-memory search
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
        final matchSource = searchIn == TmSearchScope.source ||
            searchIn == TmSearchScope.both;
        final matchTarget = searchIn == TmSearchScope.target ||
            searchIn == TmSearchScope.both;

        return (matchSource &&
                entry.sourceText.toLowerCase().contains(searchLower)) ||
            (matchTarget &&
                entry.translatedText.toLowerCase().contains(searchLower));
      }).take(limit).toList();

      return Ok(filtered);
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

  // ========== MATCHING OPERATIONS (Delegated) ==========

  @override
  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
    String? gameContext,
  }) =>
      _matchingService.findExactMatch(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        gameContext: gameContext,
      );

  @override
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    int maxResults = AppConstants.maxTmFuzzyResults,
    String? gameContext,
    String? category,
  }) =>
      _matchingService.findFuzzyMatches(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        minSimilarity: minSimilarity,
        maxResults: maxResults,
        gameContext: gameContext,
        category: category,
      );

  @override
  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    String? gameContext,
    String? category,
  }) =>
      _matchingService.findBestMatch(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        minSimilarity: minSimilarity,
        gameContext: gameContext,
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
    String? gameContext,
    double? minQuality,
  }) =>
      _importExportService.exportToTmx(
        outputPath: outputPath,
        sourceLanguageCode: sourceLanguageCode,
        targetLanguageCode: targetLanguageCode,
        gameContext: gameContext,
        minQuality: minQuality,
      );

  // ========== STATISTICS AND MAINTENANCE ==========

  @override
  Future<Result<int, TmServiceException>> cleanupLowQualityEntries({
    double minQuality = AppConstants.minTmCleanupQuality,
    int unusedDays = AppConstants.unusedTmCleanupDays,
  }) async {
    try {
      // Validate parameters
      if (minQuality < 0.0 || minQuality > 1.0) {
        return Err(
          TmServiceException(
            'minQuality must be between 0.0 and 1.0',
          ),
        );
      }

      if (unusedDays < 0) {
        return Err(
          TmServiceException(
            'unusedDays must be non-negative',
          ),
        );
      }

      _logger.info(
        'Starting TM cleanup',
        {
          'minQuality': minQuality,
          'unusedDays': unusedDays,
        },
      );

      // Delete low-quality, unused entries
      final deleteResult = await _repository.deleteByQualityAndAge(
        maxQuality: minQuality,
        unusedDays: unusedDays,
      );

      if (deleteResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to delete entries: ${deleteResult.error}',
            error: deleteResult.error,
          ),
        );
      }

      final deletedCount = deleteResult.value;

      _logger.info(
        'TM cleanup completed',
        {'deletedEntries': deletedCount},
      );

      // Clear cache after cleanup to ensure fresh data
      if (deletedCount > 0) {
        await clearCache();
      }

      return Ok(deletedCount);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error during cleanup: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<Result<TmStatistics, TmServiceException>> getStatistics({
    String? targetLanguageCode,
    String? gameContext,
  }) async {
    try {
      // Get basic statistics
      final statsResult = await _repository.getStatistics(
        targetLanguageId: targetLanguageCode,
      );

      if (statsResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to get statistics: ${statsResult.error}',
            error: statsResult.error,
          ),
        );
      }

      final statsData = statsResult.value;
      final totalEntries = statsData['total_entries'] as int;
      final avgQuality = statsData['avg_quality'] as double;
      final totalUsage = statsData['total_usage'] as int;

      // Get entries by language
      final languagePairResult = await _repository.getEntriesByLanguage();

      if (languagePairResult.isErr) {
        return Err(
          TmServiceException(
            'Failed to get language pair statistics: ${languagePairResult.error}',
            error: languagePairResult.error,
          ),
        );
      }

      final entriesByLanguagePair = languagePairResult.value;

      // Calculate estimated token reuse
      // Assumption: Average entry saves ~50 tokens per reuse
      const avgTokensPerEntry = 50;
      final tokensSaved = totalUsage * avgTokensPerEntry;

      // Calculate reuse rate
      // Note: This is a simplified calculation
      // In production, you'd compare TM hits vs total translation requests
      final reuseRate = totalEntries > 0 ? totalUsage / totalEntries : 0.0;

      final stats = TmStatistics(
        totalEntries: totalEntries,
        entriesByLanguagePair: entriesByLanguagePair,
        averageQuality: avgQuality,
        totalReuseCount: totalUsage,
        tokensSaved: tokensSaved,
        averageFuzzyScore: 0.0, // Would require separate tracking
        reuseRate: reuseRate.clamp(0.0, 1.0),
      );

      return Ok(stats);
    } catch (e, stackTrace) {
      return Err(
        TmServiceException(
          'Unexpected error getting statistics: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  Future<void> clearCache() async {
    _cache.clear();
  }

  @override
  Future<Result<void, TmServiceException>> rebuildCache({
    int maxEntries = AppConstants.maxTmCacheEntries,
  }) async {
    // TODO: Implement when repository supports getMostUsedEntries query
    // For now, just clear the cache
    _cache.clear();
    return Ok(null);
  }
}
