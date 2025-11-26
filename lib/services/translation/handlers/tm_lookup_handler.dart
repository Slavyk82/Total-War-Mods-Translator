import 'dart:async';

import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/concurrency/transaction_manager.dart';
import 'package:twmt/services/shared/logging_service.dart';
import 'package:twmt/services/translation/models/translation_context.dart';
import 'package:twmt/services/translation/models/translation_progress.dart';
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
/// - Check if units are already translated
class TmLookupHandler {
  final ITranslationMemoryService _tmService;
  final TranslationVersionRepository _versionRepository;
  final TransactionManager _transactionManager;
  final LoggingService _logger;
  final Uuid _uuid = const Uuid();

  TmLookupHandler({
    required ITranslationMemoryService tmService,
    required TranslationVersionRepository versionRepository,
    required TransactionManager transactionManager,
    required LoggingService logger,
  })  : _tmService = tmService,
        _versionRepository = versionRepository,
        _transactionManager = transactionManager,
        _logger = logger;

  /// Maximum concurrent TM lookups for READ operations (queries)
  /// These are safe to parallelize as they don't modify data
  static const int _maxConcurrentLookups = 15;

  /// Perform TM exact and fuzzy match lookup for batch units
  ///
  /// Returns updated progress with TM match statistics
  Future<TranslationProgress> performLookup({
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

    // Process exact matches in parallel chunks
    // IMPORTANT: Reads are done in parallel, but ALL writes are batched into single transaction
    final exactMatchedUnitIds = <String>{};

    for (var i = 0; i < units.length; i += _maxConcurrentLookups) {
      await checkPauseOrCancel(batchId);

      final chunk = units.skip(i).take(_maxConcurrentLookups).toList();
      final progressPct = ((i / units.length) * 100).round();
      
      // Update progress detail
      progress = progress.copyWith(
        phaseDetail: 'Exact TM lookup: $progressPct% ($i/${units.length} units, ${exactMatchedUnitIds.length} matches)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      // Phase 1: Parallel READ operations (TM lookups)
      final lookupResults = await Future.wait(
        chunk.map((unit) => _findExactMatch(unit, context)),
      );

      // Phase 2: Collect matches that need to be applied
      final matchesToApply = <_PendingTmMatch>[];
      for (var j = 0; j < chunk.length; j++) {
        final result = lookupResults[j];
        if (result != null) {
          matchesToApply.add(_PendingTmMatch(unit: chunk[j], match: result));
        }
      }

      // Phase 3: Single WRITE transaction for all matches in this chunk
      if (matchesToApply.isNotEmpty) {
        progress = progress.copyWith(
          phaseDetail: 'Applying ${matchesToApply.length} exact TM matches...',
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, progress);
        
        await _applyTmMatchesBatch(matchesToApply, context);
        for (final pending in matchesToApply) {
          exactMatchedUnitIds.add(pending.unit.id);
          skippedCount++;
          processedCount++;
        }
      }

      // Log progress periodically
      if (i % 500 == 0 && i > 0) {
        _logger.debug('TM exact lookup progress', {
          'batchId': batchId,
          'processed': i,
          'total': units.length,
          'matches': skippedCount,
        });
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

    var fuzzyMatchCount = 0;

    // Process fuzzy matches in parallel chunks
    // IMPORTANT: Reads are done in parallel, but ALL writes are batched into single transaction
    for (var i = 0; i < unitsForFuzzy.length; i += _maxConcurrentLookups) {
      await checkPauseOrCancel(batchId);

      final chunk = unitsForFuzzy.skip(i).take(_maxConcurrentLookups).toList();
      final progressPct = ((i / unitsForFuzzy.length) * 100).round();
      
      // Update progress detail
      progress = progress.copyWith(
        phaseDetail: 'Fuzzy TM lookup (≥85%): $progressPct% ($i/${unitsForFuzzy.length} units, $fuzzyMatchCount matches)...',
        timestamp: DateTime.now(),
      );
      onProgressUpdate(batchId, progress);

      // Phase 1: Parallel READ operations (TM lookups + check if already translated)
      final lookupResults = await Future.wait(
        chunk.map((unit) => _findFuzzyMatch(unit, context)),
      );

      // Phase 2: Collect matches that need to be applied (>=95% auto-accept)
      final matchesToApply = <_PendingTmMatch>[];
      for (var j = 0; j < chunk.length; j++) {
        final result = lookupResults[j];
        if (result != null &&
            result.similarityScore >= AppConstants.autoAcceptTmThreshold) {
          matchesToApply.add(_PendingTmMatch(unit: chunk[j], match: result));
        }
      }

      // Phase 3: Single WRITE transaction for all matches in this chunk
      if (matchesToApply.isNotEmpty) {
        progress = progress.copyWith(
          phaseDetail: 'Auto-accepting ${matchesToApply.length} high-confidence fuzzy matches (≥95%)...',
          timestamp: DateTime.now(),
        );
        onProgressUpdate(batchId, progress);
        
        await _applyTmMatchesBatch(matchesToApply, context);
        skippedCount += matchesToApply.length;
        processedCount += matchesToApply.length;
        fuzzyMatchCount += matchesToApply.length;
      }

      // Log progress periodically
      if (i % 500 == 0 && i > 0) {
        _logger.debug('TM fuzzy lookup progress', {
          'batchId': batchId,
          'processed': i,
          'total': unitsForFuzzy.length,
          'matches': skippedCount - exactMatchedUnitIds.length,
        });
      }
    }

    final tmReuseRate = units.isNotEmpty ? skippedCount / units.length : 0.0;
    final tmReuseRatePct = (tmReuseRate * 100).round();

    _logger.info('TM lookup completed', {
      'batchId': batchId,
      'skippedCount': skippedCount,
      'exactMatches': exactMatchedUnitIds.length,
      'fuzzyMatches': skippedCount - exactMatchedUnitIds.length,
      'tmReuseRate': tmReuseRate,
    });

    return progress.copyWith(
      phaseDetail: 'TM lookup complete: $tmReuseRatePct% reuse (${exactMatchedUnitIds.length} exact, $fuzzyMatchCount fuzzy)',
      skippedUnits: skippedCount,
      processedUnits: processedCount,
      tmReuseRate: tmReuseRate,
      timestamp: DateTime.now(),
    );
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

  /// Find fuzzy TM match for a unit (READ-ONLY operation)
  /// Returns the best match if found and unit not already translated, null otherwise
  Future<TmMatch?> _findFuzzyMatch(
    TranslationUnit unit,
    TranslationContext context,
  ) async {
    try {
      // Check if already translated
      if (await isUnitTranslated(unit, context)) {
        return null;
      }

      final fuzzyMatchesResult = await _tmService.findFuzzyMatches(
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

  /// Apply multiple TM matches in a SINGLE transaction
  /// This prevents FTS5 corruption from concurrent writes
  /// Uses upsert to handle cases where translation already exists
  Future<void> _applyTmMatchesBatch(
    List<_PendingTmMatch> matches,
    TranslationContext context,
  ) async {
    if (matches.isEmpty) return;

    final transactionResult =
        await _transactionManager.executeTransaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;

      for (final pending in matches) {
        final version = TranslationVersion(
          id: _generateId(),
          unitId: pending.unit.id,
          projectLanguageId: context.projectLanguageId,
          translatedText: pending.match.targetText,
          status: TranslationVersionStatus.translated,
          confidenceScore: pending.match.similarityScore,
          createdAt: now,
          updatedAt: now,
        );

        // Use upsert to handle existing translations (e.g., when re-translating)
        await _versionRepository.upsertWithTransaction(txn, version);
      }
      return true;
    });

    if (transactionResult.isErr) {
      throw transactionResult.unwrapErr();
    }
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
      final version = TranslationVersion(
        id: _generateId(),
        unitId: unit.id,
        projectLanguageId: context.projectLanguageId,
        translatedText: match.targetText,
        status: TranslationVersionStatus.translated,
        confidenceScore: match.similarityScore,
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
