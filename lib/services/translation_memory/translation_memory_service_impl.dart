import 'dart:async';
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
import 'package:twmt/services/shared/logging_service.dart';

/// Implementation of Translation Memory Service
///
/// This service manages translation memory operations including:
/// - Adding translations with deduplication
/// - Exact and fuzzy match lookup (delegated to TmMatchingService)
/// - TMX import/export (delegated to TmImportExportService)
/// - Usage tracking
/// - Cache management
///
/// Service responsibilities:
/// - Coordinate between repository, matching, and import/export services
/// - Handle CRUD operations for TM entries
/// - Manage entry validation
/// - Provide statistics and maintenance operations
class TranslationMemoryServiceImpl implements ITranslationMemoryService {
  final TranslationMemoryRepository _repository;
  final LanguageRepository _languageRepository;
  final TextNormalizer _normalizer;
  final TmCache _cache;
  final LoggingService _logger;

  // Cache for language code → ID mapping
  final Map<String, String> _languageCodeToId = {};

  // Delegated services
  final TmMatchingService _matchingService;
  final TmImportExportService _importExportService;

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
        _cache = cache,
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
        // Entry exists, update usage count
        final existing = existingResult.value;
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

        _logger.debug(
          'Updated existing TM entry',
          {'entryId': existing.id},
        );

        return Ok(updateResult.value);
      }

      // Create new entry with UUID for unique identification
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
          id: const Uuid().v4(), // Unique UUID for each entry
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

  @override
  Future<Result<TranslationMemoryEntry, TmServiceException>>
      incrementUsageCount({
    required String entryId,
  }) async {
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
        _logger.error('incrementUsageCount failed', {'entryId': entryId, 'error': updateResult.error});
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

  @override
  Future<Result<List<TranslationMemoryEntry>, TmServiceException>> getEntries({
    String? targetLanguageCode,
    int limit = AppConstants.defaultTmPageSize,
    int offset = 0,
    String orderBy = 'usage_count DESC',
  }) async {
    try {
      // Convert language code to ID format (e.g., 'fr' -> 'lang_fr')
      final targetLanguageId = targetLanguageCode != null
          ? 'lang_$targetLanguageCode'
          : null;

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

  @override
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

      // Convert language code to ID format (e.g., 'fr' -> 'lang_fr')
      final targetLanguageId = targetLanguageCode != null
          ? 'lang_$targetLanguageCode'
          : null;

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
        _logger.debug(
          'FTS5 search completed',
          {
            'query': searchText,
            'scope': searchScope,
            'resultsCount': ftsResult.value.length,
          },
        );
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
  /// This method loads all entries and filters in-memory.
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
          'Unexpected error in fallback search: ${e.toString()}',
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

  // ========== STATISTICS AND MAINTENANCE ==========

  @override
  Future<Result<int, TmServiceException>> cleanupUnusedEntries({
    int unusedDays = AppConstants.unusedTmCleanupDays,
  }) async {
    try {
      if (unusedDays < 0) {
        return Err(
          TmServiceException(
            'unusedDays must be non-negative',
          ),
        );
      }

      // Calculate cutoff for debugging
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final cutoffTimestamp = now - (unusedDays * 24 * 60 * 60);
      final cutoffDate = DateTime.fromMillisecondsSinceEpoch(cutoffTimestamp * 1000);

      _logger.info(
        'Starting TM cleanup',
        {
          'unusedDays': unusedDays,
          'cutoffDate': cutoffDate.toIso8601String(),
          'cutoffTimestamp': cutoffTimestamp,
        },
      );

      // First, count candidates for diagnostic purposes
      final countResult = await _repository.countCleanupCandidates(
        unusedDays: unusedDays,
      );

      if (countResult.isOk) {
        final counts = countResult.value;
        _logger.info(
          'TM cleanup candidates analysis',
          {
            'willBeDeleted': counts['willBeDeleted'],
            'unusedOnly': counts['unusedOnly'],
          },
        );
      }

      // Delete unused entries
      final deleteResult = await _repository.deleteByAge(
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
  }) async {
    try {
      // Convert language code to ID format (e.g., 'fr' -> 'lang_fr')
      final targetLanguageId = targetLanguageCode != null
          ? 'lang_$targetLanguageCode'
          : null;

      // Get basic statistics
      final statsResult = await _repository.getStatistics(
        targetLanguageId: targetLanguageId,
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

      // Resolve language IDs to display names
      final languageIds = languagePairResult.value.keys.toList();
      final languagesResult = await _languageRepository.getByIds(languageIds);

      // Build a map of ID -> display name
      final idToDisplayName = <String, String>{};
      if (languagesResult.isOk) {
        for (final lang in languagesResult.value) {
          idToDisplayName[lang.id] = lang.name;
        }
      }

      // Convert UUIDs to display names in the result
      final entriesByLanguagePair = <String, int>{};
      for (final entry in languagePairResult.value.entries) {
        final displayName = idToDisplayName[entry.key] ?? entry.key;
        entriesByLanguagePair[displayName] = entry.value;
      }

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
