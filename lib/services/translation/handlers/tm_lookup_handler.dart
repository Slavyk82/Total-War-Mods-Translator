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

  /// Perform TM exact and fuzzy match lookup for batch units
  ///
  /// Returns updated progress with TM match statistics
  Future<TranslationProgress> performLookup({
    required String batchId,
    required List<TranslationUnit> units,
    required TranslationContext context,
    required TranslationProgress currentProgress,
    required Future<void> Function(String batchId) checkPauseOrCancel,
  }) async {
    _logger.info('Starting TM lookup', {'batchId': batchId});

    var progress = currentProgress.copyWith(
      currentPhase: TranslationPhase.tmExactLookup,
      timestamp: DateTime.now(),
    );

    var skippedCount = 0;
    var processedCount = 0;

    // Check exact matches first
    for (final unit in units) {
      await checkPauseOrCancel(batchId);

      final exactMatchResult = await _tmService.findExactMatch(
        sourceText: unit.sourceText,
        targetLanguageCode: context.targetLanguage,
        gameContext: context.gameContext,
      );

      if (exactMatchResult.isOk && exactMatchResult.unwrap() != null) {
        final match = exactMatchResult.unwrap()!;

        // Apply exact match directly (100% match, skip LLM)
        await applyTmMatch(unit, match, context);

        skippedCount++;
        processedCount++;
      }
    }

    // Check fuzzy matches for remaining units
    progress = progress.copyWith(
      currentPhase: TranslationPhase.tmFuzzyLookup,
      skippedUnits: skippedCount,
      processedUnits: processedCount,
      timestamp: DateTime.now(),
    );

    for (final unit in units) {
      await checkPauseOrCancel(batchId);

      // Skip if already matched exactly
      if (await isUnitTranslated(unit, context)) {
        continue;
      }

      final fuzzyMatchesResult = await _tmService.findFuzzyMatches(
        sourceText: unit.sourceText,
        targetLanguageCode: context.targetLanguage,
        minSimilarity: AppConstants.minTmSimilarity,
        maxResults: AppConstants.maxTmFuzzyResults,
        gameContext: context.gameContext,
        category: context.category,
      );

      if (fuzzyMatchesResult.isOk && fuzzyMatchesResult.unwrap().isNotEmpty) {
        final matches = fuzzyMatchesResult.unwrap();
        final bestMatch = matches.first;

        // Auto-accept if similarity >= 95%
        if (bestMatch.similarityScore >= AppConstants.autoAcceptTmThreshold) {
          await applyTmMatch(unit, bestMatch, context);
          skippedCount++;
          processedCount++;
        }
        // Otherwise, store as suggestion for manual review (85-95%)
      }
    }

    final tmReuseRate = units.isNotEmpty ? skippedCount / units.length : 0.0;

    _logger.info('TM lookup completed', {
      'batchId': batchId,
      'skippedCount': skippedCount,
      'tmReuseRate': tmReuseRate,
    });

    return progress.copyWith(
      skippedUnits: skippedCount,
      processedUnits: processedCount,
      tmReuseRate: tmReuseRate,
      timestamp: DateTime.now(),
    );
  }

  /// Apply a TM match to a unit (save to database)
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
        status: match.similarityScore >= AppConstants.exactMatchSimilarity
            ? TranslationVersionStatus.approved
            : TranslationVersionStatus.translated,
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
