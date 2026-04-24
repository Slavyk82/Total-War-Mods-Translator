import 'dart:async';

import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/models/history/history_change_entry.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/history/i_history_service.dart';
import 'package:twmt/services/shared/i_logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
import 'package:twmt/services/translation/utils/translation_text_utils.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:uuid/uuid.dart';

/// Handles Translation Memory exact and fuzzy matching operations
///
/// Responsibilities:
/// - Find exact matches in TM (100% similarity, skip LLM)
/// - Find fuzzy matches in TM (>=85% similarity)
/// - Auto-accept fuzzy matches >=95%
/// - Apply TM matches to translation units
/// - Record translation history for TM matches
/// - Check if units are already translated
class TmLookupHandler {
  final ITranslationMemoryService _tmService;
  final IHistoryService _historyService;
  final TranslationVersionRepository _versionRepository;
  final TransactionManager _transactionManager;
  final ILoggingService _logger;
  final Uuid _uuid = const Uuid();

  TmLookupHandler({
    required ITranslationMemoryService tmService,
    required IHistoryService historyService,
    required TranslationVersionRepository versionRepository,
    required TransactionManager transactionManager,
    required ILoggingService logger,
  })  : _tmService = tmService,
        _historyService = historyService,
        _versionRepository = versionRepository,
        _transactionManager = transactionManager,
        _logger = logger;

  /// Maximum concurrent TM lookups for READ operations (queries).
  /// These are safe to parallelize as they don't modify data.
  static const int _maxConcurrentLookups = 50;

  /// Perform TM exact and fuzzy match lookup for batch units
  ///
  /// Returns tuple of (updated progress, set of matched unit IDs)
  /// The matched unit IDs can be used to skip re-checking in subsequent phases.
  Future<(TranslationProgress, Set<String>)> performLookup({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Future<void> Function(String batchId) checkPauseOrCancel,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
  }) async {
    _logger.info('Starting TM lookup', {
      'batchId': batchId,
      'totalUnits': units.length,
    });

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.tmExactLookup,
      phaseDetail: 'Searching exact matches in Translation Memory (${units.length} units)...',
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    var skippedCount = 0;
    var processedCount = 0;

    // Accumulate usage counts across all chunks for a single batch increment at the end
    final allEntryUsageCounts = <String, int>{};

    // === EXACT LOOKUP PHASE (collect only) ===
    final allExactMatches = <_PendingTmMatch>[];
    for (var i = 0; i < units.length; i += _maxConcurrentLookups) {
      await checkPauseOrCancel(batchId);

      final chunk = units.skip(i).take(_maxConcurrentLookups).toList();
      final progressPct = ((i / units.length) * 100).round();
      progress = progress.copyWith(
        phaseDetail:
            'Exact TM lookup: $progressPct% ($i/${units.length} units, ${allExactMatches.length} matches)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      if (i % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final lookupResults = await Future.wait(
        chunk.map((unit) => _findExactMatch(unit, context)),
      );
      for (var j = 0; j < chunk.length; j++) {
        final result = lookupResults[j];
        if (result != null) {
          allExactMatches.add(_PendingTmMatch(unit: chunk[j], match: result));
        }
      }

      if (i % 500 == 0 && i > 0) {
        _logger.debug('TM exact lookup progress', {
          'batchId': batchId,
          'processed': i,
          'total': units.length,
          'matches': allExactMatches.length,
        });
      }
    }

    // === EXACT APPLY PHASE (single bulk write) ===
    final exactMatchedUnitIds = <String>{};
    if (allExactMatches.isNotEmpty) {
      progress = progress.copyWith(
        phaseDetail: 'Applying ${allExactMatches.length} exact TM matches...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      final applyCounts = await _applyTmMatchesBatch(
        allExactMatches,
        context,
        batchId: batchId,
        phasePrefix: 'Applying ${allExactMatches.length} exact TM matches',
        progress: progress,
        onProgressUpdate: onProgressUpdate,
      );
      for (final pending in allExactMatches) {
        exactMatchedUnitIds.add(pending.unit.id);
      }
      skippedCount += allExactMatches.length;
      processedCount += allExactMatches.length;
      for (final entry in applyCounts.entries) {
        allEntryUsageCounts.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }

    // Update progress for fuzzy phase
    progress = progress.copyWith(
      currentPhase: TranslationPhase.tmFuzzyLookup,
      phaseDetail: 'Exact lookup complete: ${exactMatchedUnitIds.length} matches found. Starting fuzzy search...',
      skippedUnits: skippedCount,
      processedUnits: processedCount,
      timestamp: DateTime.now(),
    );
    onProgressUpdate(batchId, progress);

    // Filter units that need fuzzy matching (not already exact matched)
    final unitsForFuzzy = units.where((u) => !exactMatchedUnitIds.contains(u.id)).toList();

    _logger.info('Starting fuzzy TM lookup', {
      'batchId': batchId,
      'unitsForFuzzy': unitsForFuzzy.length,
      'exactMatched': exactMatchedUnitIds.length,
    });

    // Pre-fetch all translated unit IDs in one batch query (optimization)
    // This avoids N sequential DB queries during fuzzy matching
    final fuzzyUnitIds = unitsForFuzzy.map((u) => u.id).toList();
    final alreadyTranslatedIdsResult = await _versionRepository.getTranslatedUnitIds(
      unitIds: fuzzyUnitIds,
      projectLanguageId: context.projectLanguageId,
    );
    final alreadyTranslatedIds = alreadyTranslatedIdsResult.isOk
        ? alreadyTranslatedIdsResult.unwrap()
        : <String>{};

    // Further filter to exclude already translated units
    final unitsForFuzzyFiltered = unitsForFuzzy
        .where((u) => !alreadyTranslatedIds.contains(u.id))
        .toList();

    _logger.debug('Fuzzy lookup after pre-filter', {
      'batchId': batchId,
      'beforeFilter': unitsForFuzzy.length,
      'afterFilter': unitsForFuzzyFiltered.length,
      'alreadyTranslated': alreadyTranslatedIds.length,
    });

    // === FUZZY LOOKUP PHASE (collect only) ===
    final allFuzzyMatches = <_PendingTmMatch>[];
    for (var i = 0; i < unitsForFuzzyFiltered.length; i += _maxConcurrentLookups) {
      await checkPauseOrCancel(batchId);

      final chunk =
          unitsForFuzzyFiltered.skip(i).take(_maxConcurrentLookups).toList();
      final progressPct =
          ((i / unitsForFuzzyFiltered.length) * 100).round();
      progress = progress.copyWith(
        phaseDetail:
            'Fuzzy TM lookup (≥85%): $progressPct% ($i/${unitsForFuzzyFiltered.length} units, ${allFuzzyMatches.length} matches)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      if (i % 100 == 0) {
        await Future<void>.delayed(Duration.zero);
      }

      final lookupResults = await Future.wait(
        chunk.map((unit) => _findFuzzyMatch(unit, context)),
      );
      for (var j = 0; j < chunk.length; j++) {
        final result = lookupResults[j];
        if (result != null &&
            result.similarityScore >= AppConstants.autoAcceptTmThreshold) {
          allFuzzyMatches.add(_PendingTmMatch(unit: chunk[j], match: result));
        }
      }
    }

    // === FUZZY APPLY PHASE (single bulk write) ===
    final fuzzyMatchedUnitIds = <String>{};
    var fuzzyMatchCount = 0;
    if (allFuzzyMatches.isNotEmpty) {
      progress = progress.copyWith(
        phaseDetail:
            'Auto-accepting ${allFuzzyMatches.length} high-confidence fuzzy matches (≥95%)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      final applyCounts = await _applyTmMatchesBatch(
        allFuzzyMatches,
        context,
        batchId: batchId,
        phasePrefix: 'Auto-accepting ${allFuzzyMatches.length} high-confidence fuzzy matches (≥95%)',
        progress: progress,
        onProgressUpdate: onProgressUpdate,
      );
      for (final pending in allFuzzyMatches) {
        fuzzyMatchedUnitIds.add(pending.unit.id);
      }
      fuzzyMatchCount = allFuzzyMatches.length;
      skippedCount += allFuzzyMatches.length;
      processedCount += allFuzzyMatches.length;
      for (final entry in applyCounts.entries) {
        allEntryUsageCounts.update(entry.key, (v) => v + entry.value,
            ifAbsent: () => entry.value);
      }
    }

    final tmReuseRate = units.isNotEmpty ? skippedCount / units.length : 0.0;
    final tmReuseRatePct = (tmReuseRate * 100).round();

    _logger.info('TM lookup completed', {
      'batchId': batchId,
      'skippedCount': skippedCount,
      'exactMatches': exactMatchedUnitIds.length,
      'fuzzyMatches': fuzzyMatchedUnitIds.length,
      'tmReuseRate': tmReuseRate,
    });

    // Single batch increment for ALL usage counts accumulated across all chunks
    if (allEntryUsageCounts.isNotEmpty) {
      try {
        await _tmService.incrementUsageCountBatch(allEntryUsageCounts);
      } catch (e) {
        _logger.warning('Failed to batch increment TM usage counts (non-critical)', {
          'entryCount': allEntryUsageCounts.length,
          'error': e,
        });
      }
    }

    // Combine all matched unit IDs (exact + fuzzy)
    final allMatchedUnitIds = <String>{...exactMatchedUnitIds, ...fuzzyMatchedUnitIds};

    final finalProgress = progress.copyWith(
      phaseDetail: 'TM lookup complete: $tmReuseRatePct% reuse (${exactMatchedUnitIds.length} exact, $fuzzyMatchCount fuzzy)',
      skippedUnits: skippedCount,
      processedUnits: processedCount,
      tmReuseRate: tmReuseRate,
      timestamp: DateTime.now(),
    );

    return (finalProgress, allMatchedUnitIds);
  }

  /// Find exact TM match for a unit (READ-ONLY operation)
  /// Returns the match if found, null otherwise
  Future<TmMatch?> _findExactMatch(
    TranslationUnit unit,
    TranslationContext context,
  ) async {
    try {
      final exactMatchResult = await _tmService.findExactMatch(
        sourceText: unit.sourceText,
        targetLanguageCode: context.targetLanguage,
      );

      if (exactMatchResult.isOk && exactMatchResult.unwrap() != null) {
        return exactMatchResult.unwrap()!;
      }
    } catch (e) {
      _logger.warning('Error in exact TM match', {'unitId': unit.id, 'error': e});
    }
    return null;
  }

  /// Find fuzzy TM match for a unit using isolate (READ-ONLY operation)
  /// Returns the best match if found, null otherwise.
  /// Note: Already-translated units should be filtered out before calling this method.
  /// Uses isolate-based computation to prevent UI freezing.
  Future<TmMatch?> _findFuzzyMatch(
    TranslationUnit unit,
    TranslationContext context,
  ) async {
    try {
      // Use isolate-based fuzzy matching to prevent UI freezing
      final fuzzyMatchesResult = await _tmService.findFuzzyMatchesIsolate(
        sourceText: unit.sourceText,
        targetLanguageCode: context.targetLanguage,
        minSimilarity: AppConstants.minTmSimilarity,
        maxResults: AppConstants.maxTmFuzzyResults,
        category: context.category,
      );

      if (fuzzyMatchesResult.isOk && fuzzyMatchesResult.unwrap().isNotEmpty) {
        return fuzzyMatchesResult.unwrap().first;
      }
    } catch (e) {
      _logger.warning('Error in fuzzy TM match', {'unitId': unit.id, 'error': e});
    }
    return null;
  }

  /// Apply a collected set of TM matches in a single optimized bulk write.
  /// Returns a map of entry IDs → applied count, for deferred usage increment.
  Future<Map<String, int>> _applyTmMatchesBatch(
    List<_PendingTmMatch> matches,
    TranslationContext context, {
    required String batchId,
    required String phasePrefix,
    required TranslationProgress progress,
    required void Function(String batchId, TranslationProgress progress) onProgressUpdate,
  }) async {
    if (matches.isEmpty) return {};

    final now = DateTime.now().millisecondsSinceEpoch;

    // Build TranslationVersion entities aligned by index with `matches`.
    final versions = <TranslationVersion>[];
    for (final pending in matches) {
      final translationSource = pending.match.matchType == TmMatchType.exact
          ? TranslationSource.tmExact
          : TranslationSource.tmFuzzy;
      final normalizedText =
          TranslationTextUtils.normalizeTranslation(pending.match.targetText);
      versions.add(TranslationVersion(
        id: _generateId(),
        unitId: pending.unit.id,
        projectLanguageId: context.projectLanguageId,
        translatedText: normalizedText,
        status: TranslationVersionStatus.translated,
        translationSource: translationSource,
        createdAt: now,
        updatedAt: now,
      ));
    }

    // Single bulk write.
    final upsertResult = await _versionRepository.upsertBatchOptimized(
      entities: versions,
      onProgress: (current, total, message) {
        final updated = progress.copyWith(
          phaseDetail: '$phasePrefix — $message',
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, updated);
      },
    );
    if (upsertResult.isErr) {
      throw upsertResult.unwrapErr();
    }
    final effectiveIds = upsertResult.unwrap().effectiveVersionIds;
    assert(effectiveIds.length == matches.length,
        'upsertBatchOptimized returned mismatched effectiveVersionIds length');

    // Build history entries keyed off the REAL persisted ids.
    final historyEntries = <HistoryChangeEntry>[];
    for (var i = 0; i < matches.length; i++) {
      final pending = matches[i];
      final matchType =
          pending.match.matchType == TmMatchType.exact ? 'exact' : 'fuzzy';
      final similarity = (pending.match.similarityScore * 100).round();
      historyEntries.add(HistoryChangeEntry(
        versionId: effectiveIds[i],
        translatedText: versions[i].translatedText ?? '',
        status: TranslationVersionStatus.translated.name,
        changedBy: 'tm_$matchType',
        changeReason: 'TM $matchType match ($similarity% similarity)',
      ));
    }
    final historyResult =
        await _historyService.recordChangesBatch(historyEntries);
    if (historyResult.isErr) {
      // Non-critical: keep current behaviour, just log.
      _logger.warning('Failed to batch-record TM history (non-critical)', {
        'count': historyEntries.length,
        'error': historyResult.unwrapErr(),
      });
    }

    // Accumulate usage counts per TM entry.
    final entryUsageCounts = <String, int>{};
    for (final pending in matches) {
      entryUsageCounts.update(
        pending.match.entryId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return entryUsageCounts;
  }

  /// Apply a TM match to a unit (save to database) - DEPRECATED, use _applyTmMatchesBatch
  @Deprecated('Use _applyTmMatchesBatch for batch operations to prevent FTS5 corruption')
  Future<void> applyTmMatch(
    TranslationUnit unit,
    TmMatch match,
    TranslationContext context,
  ) async {
    final transactionResult =
        await _transactionManager.executeTransaction((txn) async {
      // Determine translation source based on TM match type
      final translationSource = match.matchType == TmMatchType.exact
          ? TranslationSource.tmExact
          : TranslationSource.tmFuzzy;

      // Normalize: \\n → \n
      final normalizedText = TranslationTextUtils.normalizeTranslation(match.targetText);

      final version = TranslationVersion(
        id: _generateId(),
        unitId: unit.id,
        projectLanguageId: context.projectLanguageId,
        translatedText: normalizedText,
        status: TranslationVersionStatus.translated,
        translationSource: translationSource,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await _versionRepository.insert(version);
      return true;
    });

    if (transactionResult.isErr) {
      throw transactionResult.unwrapErr();
    }
  }

  /// Check if a unit is already translated
  Future<bool> isUnitTranslated(
      TranslationUnit unit, TranslationContext context) async {
    final versionsResult = await _versionRepository.getByUnit(unit.id);

    if (versionsResult.isOk && versionsResult.unwrap().isNotEmpty) {
      final version = versionsResult.unwrap().first;
      // Check if the version has actual translated text
      return version.translatedText != null && version.translatedText!.isNotEmpty;
    }

    return false;
  }

  /// Generate a unique ID (UUID v4)
  String _generateId() => _uuid.v4();
}

/// Internal class for pending TM match writes
class _PendingTmMatch {
  final TranslationUnit unit;
  final TmMatch match;

  const _PendingTmMatch({
    required this.unit,
    required this.match,
  });
}
