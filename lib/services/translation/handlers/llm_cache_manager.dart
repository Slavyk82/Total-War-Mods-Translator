import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/batch_translation_cache.dart';
import 'package:twmt/services/translation/models/translation_context.dart';

/// Result of processing cache for translation units.
class CacheProcessingResult {
  /// Translations already available from cache.
  final Map<String, String> cachedTranslations;

  /// Source texts that need to be translated via LLM.
  final List<String> uncachedSourceTexts;

  /// Hashes that were registered as pending for this batch.
  final Map<String, String> registeredHashes;

  /// Mapping from source text to units that share that text.
  final Map<String, List<TranslationUnit>> sourceTextToUnits;

  /// Unit IDs that received their translation from cache.
  final Set<String> cachedUnitIds;

  /// All translations (unitId -> translation) built so far.
  final Map<String, String> allTranslations;

  CacheProcessingResult({
    required this.cachedTranslations,
    required this.uncachedSourceTexts,
    required this.registeredHashes,
    required this.sourceTextToUnits,
    required this.cachedUnitIds,
    required this.allTranslations,
  });
}

/// Manages cache operations for LLM translation batches.
///
/// Responsibilities:
/// - Deduplicate units by source text within a batch
/// - Check cache for existing translations
/// - Wait for pending translations from parallel batches
/// - Register pending translations
/// - Update cache with completed translations
class LlmCacheManager {
  final LoggingService _logger;
  final BatchTranslationCache _cache = BatchTranslationCache.instance;

  LlmCacheManager({required LoggingService logger}) : _logger = logger;

  /// Process units to find cached translations and identify what needs LLM translation.
  ///
  /// Returns a [CacheProcessingResult] containing:
  /// - Cached translations ready to use
  /// - Source texts that need LLM translation
  /// - Registered hashes for tracking
  /// - Mapping of source text to units
  Future<CacheProcessingResult> processUnitsForCache({
    required String batchId,
    required List<TranslationUnit> unitsToTranslate,
    required TranslationContext context,
    required void Function(String batchId, String phaseDetail) onProgressUpdate,
  }) async {
    const yieldInterval = 500;
    var yieldCounter = 0;

    // === DEDUPLICATION: Group units by source text ===
    final sourceTextToUnits = <String, List<TranslationUnit>>{};

    // Update progress for large batches
    if (unitsToTranslate.length > 1000) {
      onProgressUpdate(
        batchId,
        'Deduplicating ${unitsToTranslate.length} units...',
      );
    }

    for (final unit in unitsToTranslate) {
      sourceTextToUnits.putIfAbsent(unit.sourceText, () => []).add(unit);

      // Yield to event loop periodically to prevent UI freeze
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    final uniqueSourceTexts = sourceTextToUnits.keys.toList();
    final duplicateCount = unitsToTranslate.length - uniqueSourceTexts.length;

    if (duplicateCount > 0) {
      _logger.info(
        'Deduplication: ${unitsToTranslate.length} units -> ${uniqueSourceTexts.length} unique texts ($duplicateCount duplicates)',
      );
    }

    // === CACHE CHECK: Find cached and pending translations ===
    final cachedTranslations = <String, String>{};
    final pendingFutures = <String, Future<String?>>{};
    final uncachedSourceTexts = <String>[];

    // When skipTranslationMemory is true, bypass cache to get fresh LLM translations
    final skipCacheLookup = context.skipTranslationMemory;

    // Update progress for large batches
    if (uniqueSourceTexts.length > 1000) {
      onProgressUpdate(
        batchId,
        skipCacheLookup
            ? 'Preparing ${uniqueSourceTexts.length} unique texts for fresh LLM translation...'
            : 'Checking cache for ${uniqueSourceTexts.length} unique texts...',
      );
    }

    yieldCounter = 0;
    for (final sourceText in uniqueSourceTexts) {
      final hash = _cache.computeHash(sourceText, context.targetLanguage);

      // Skip cache lookup when skipTranslationMemory=true to force fresh translations
      if (skipCacheLookup) {
        uncachedSourceTexts.add(sourceText);
      } else {
        final result = _cache.lookup(hash);

        switch (result) {
          case CacheHit(:final translation):
            cachedTranslations[sourceText] = translation;
          case CachePending(:final future):
            pendingFutures[sourceText] = future;
          case CacheMiss():
            uncachedSourceTexts.add(sourceText);
        }
      }

      // Yield to event loop periodically
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    if (skipCacheLookup) {
      _logger.info('Cache bypassed (skipTranslationMemory=true)', {
        'uniqueTexts': uniqueSourceTexts.length,
        'reason': 'Force fresh LLM translations to update Translation Memory',
      });
    } else if (cachedTranslations.isNotEmpty || pendingFutures.isNotEmpty) {
      _logger.info('Cache status', {
        'cached': cachedTranslations.length,
        'pending': pendingFutures.length,
        'uncached': uncachedSourceTexts.length,
      });
    }

    // === WAIT FOR PENDING: Get translations from other batches ===
    if (pendingFutures.isNotEmpty) {
      onProgressUpdate(
        batchId,
        'Waiting for ${pendingFutures.length} translations from parallel batches...',
      );

      for (final entry in pendingFutures.entries) {
        final translation = await entry.value;
        if (translation != null) {
          cachedTranslations[entry.key] = translation;
        } else {
          // Other batch failed, we need to translate this ourselves
          uncachedSourceTexts.add(entry.key);
        }
      }
    }

    // === BUILD INITIAL TRANSLATIONS MAP ===
    final allTranslations = <String, String>{};
    final cachedUnitIds = <String>{};

    // Apply cached translations to all units with same source text
    yieldCounter = 0;
    for (final entry in cachedTranslations.entries) {
      final unitsWithSameSource = sourceTextToUnits[entry.key] ?? [];
      for (final unit in unitsWithSameSource) {
        allTranslations[unit.id] = entry.value;
        cachedUnitIds.add(unit.id);
      }

      // Yield to event loop periodically
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // === REGISTER PENDING: Mark our translations as in-progress ===
    final registeredHashes = <String, String>{};
    yieldCounter = 0;
    for (final sourceText in uncachedSourceTexts) {
      final hash = _cache.computeHash(sourceText, context.targetLanguage);
      if (_cache.registerPending(hash, batchId)) {
        registeredHashes[sourceText] = hash;
      }

      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    return CacheProcessingResult(
      cachedTranslations: cachedTranslations,
      uncachedSourceTexts: uncachedSourceTexts,
      registeredHashes: registeredHashes,
      sourceTextToUnits: sourceTextToUnits,
      cachedUnitIds: cachedUnitIds,
      allTranslations: allTranslations,
    );
  }

  /// Update cache with LLM translations and apply to all duplicate units.
  ///
  /// [cachedUnitIds] is updated with IDs of duplicate units (not the representative
  /// unit that was actually translated by LLM).
  Future<void> updateCacheAndApplyDuplicates({
    required Map<String, String> llmTranslations,
    required Map<String, List<TranslationUnit>> sourceTextToUnits,
    required Map<String, String> registeredHashes,
    required Map<String, String> allTranslations,
    required Set<String> cachedUnitIds,
    required TranslationContext context,
  }) async {
    const yieldInterval = 500;
    var yieldCounter = 0;

    // For each LLM translation, update cache and apply to all units with same source
    for (final entry in llmTranslations.entries) {
      final unitId = entry.key;
      final translation = entry.value;

      // Find the source text for this unit
      String? sourceText;
      for (final stEntry in sourceTextToUnits.entries) {
        if (stEntry.value.any((u) => u.id == unitId)) {
          sourceText = stEntry.key;
          break;
        }
      }

      if (sourceText == null) continue;

      // Update cache
      final hash = registeredHashes[sourceText];
      if (hash != null) {
        _cache.complete(hash, translation);
      }

      // Apply translation to all units with same source text
      // Mark duplicates (units other than the representative) as cached
      final unitsWithSameSource = sourceTextToUnits[sourceText] ?? [];
      for (final unit in unitsWithSameSource) {
        allTranslations[unit.id] = translation;
        // If this is not the unit that was actually translated by LLM, mark as cached
        if (unit.id != unitId) {
          cachedUnitIds.add(unit.id);
        }
      }

      // Yield to event loop periodically
      if (++yieldCounter % yieldInterval == 0) {
        await Future.delayed(Duration.zero);
      }
    }

    // Fail any registered hashes that didn't get a translation
    for (final entry in registeredHashes.entries) {
      final sourceText = entry.key;
      final hash = entry.value;

      // Check if we got a translation for this source text
      final units = sourceTextToUnits[sourceText] ?? [];
      final hasTranslation = units.any((u) => allTranslations.containsKey(u.id));

      if (!hasTranslation) {
        _cache.fail(hash);
      }
    }
  }

  /// Fail all registered pending translations (on error).
  void failRegisteredHashes(Map<String, String> registeredHashes) {
    for (final hash in registeredHashes.values) {
      _cache.fail(hash);
    }
  }

  /// Compute hash for a source text and target language.
  String computeHash(String sourceText, String targetLanguage) {
    return _cache.computeHash(sourceText, targetLanguage);
  }
}
