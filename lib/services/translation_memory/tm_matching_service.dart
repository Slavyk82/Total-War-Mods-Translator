import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/isolate_similarity_service.dart';

/// Translation Memory matching service
///
/// Handles:
/// - Exact match lookup (hash-based, O(1))
/// - Fuzzy match lookup (3 algorithms combined)
/// - Best match selection
/// - Context-aware matching
/// - Quality scoring
class TmMatchingService {
  final TranslationMemoryRepository _repository;
  final LanguageRepository _languageRepository;
  final TextNormalizer _normalizer;
  final SimilarityCalculator _similarityCalculator;
  final TmCache _cache;

  // Cache for language code → ID mapping
  final Map<String, String> _languageCodeToId = {};

  TmMatchingService({
    required TranslationMemoryRepository repository,
    required LanguageRepository languageRepository,
    required TextNormalizer normalizer,
    required SimilarityCalculator similarityCalculator,
    required TmCache cache,
  })  : _repository = repository,
        _languageRepository = languageRepository,
        _normalizer = normalizer,
        _similarityCalculator = similarityCalculator,
        _cache = cache;

  /// Resolve language code to database ID (with caching)
  Future<String?> _resolveLanguageId(String languageCode) async {
    if (_languageCodeToId.containsKey(languageCode)) {
      return _languageCodeToId[languageCode];
    }

    final result = await _languageRepository.getByCode(languageCode);
    if (result.isOk) {
      final languageId = result.unwrap().id;
      _languageCodeToId[languageCode] = languageId;
      return languageId;
    }
    return null;
  }

  Future<Result<TmMatch?, TmLookupException>> findExactMatch({
    required String sourceText,
    required String targetLanguageCode,
  }) async {
    try {
      // Calculate source hash using SHA256 for collision resistance
      final normalized = _normalizer.normalize(sourceText);
      final sourceHash = sha256.convert(utf8.encode(normalized)).toString();

      // Resolve language code to database ID
      final targetLanguageId = await _resolveLanguageId(targetLanguageCode);
      if (targetLanguageId == null) {
        // Language not found - no matches possible
        return Ok(null);
      }

      // Build cache key
      final cacheKey = '$sourceHash:$targetLanguageCode';

      // Check cache first
      final cached = _cache.getExactMatch(cacheKey);
      if (cached != null) {
        return Ok(cached);
      }

      // Lookup in repository
      final result = await _repository.findByHash(
        sourceHash,
        targetLanguageId,
      );

      if (result.isErr) {
        // Not found is okay for exact match
        _cache.putExactMatch(cacheKey, null);
        return Ok(null);
      }

      final entry = result.value;

      // Create TmMatch with 100% similarity
      final breakdown = SimilarityBreakdown(
        levenshteinScore: AppConstants.exactMatchSimilarity,
        jaroWinklerScore: AppConstants.exactMatchSimilarity,
        tokenScore: AppConstants.exactMatchSimilarity,
        contextBoost: AppConstants.zeroSimilarity,
        weights: const ScoreWeights(),
      );

      final match = TmMatch(
        entryId: entry.id,
        sourceText: entry.sourceText,
        targetText: entry.translatedText,
        targetLanguageCode: targetLanguageCode,
        similarityScore: AppConstants.exactMatchSimilarity,
        matchType: TmMatchType.exact,
        breakdown: breakdown,
        usageCount: entry.usageCount,
        lastUsedAt: DateTime.fromMillisecondsSinceEpoch(entry.lastUsedAt * 1000),
        qualityScore: entry.qualityScore ?? AppConstants.defaultTmQuality,
        autoApplied: true,
      );

      // Cache the result
      _cache.putExactMatch(cacheKey, match);

      return Ok(match);
    } catch (e, stackTrace) {
      return Err(
        TmLookupException(
          'Unexpected error finding exact match: ${e.toString()}',
          sourceText,
          targetLanguageCode,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatches({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    int maxResults = AppConstants.maxTmFuzzyResults,
    String? category,
  }) async {
    try {
      // Validate input
      if (minSimilarity < AppConstants.minSimilarityClamp || minSimilarity > AppConstants.maxSimilarityClamp) {
        return Err(
          TmLookupException(
            'Minimum similarity must be between ${AppConstants.minSimilarityClamp} and ${AppConstants.maxSimilarityClamp}',
            sourceText,
            targetLanguageCode,
          ),
        );
      }

      if (maxResults <= 0) {
        return Err(
          TmLookupException(
            'Maximum results must be positive',
            sourceText,
            targetLanguageCode,
          ),
        );
      }

      // Resolve language code to database ID
      final targetLanguageId = await _resolveLanguageId(targetLanguageCode);
      if (targetLanguageId == null) {
        // Language not found - no matches possible
        return Ok([]);
      }

      // Use repository's findMatches method
      final candidatesResult = await _repository.findMatches(
        sourceText,
        targetLanguageId,
        minConfidence: minSimilarity,
      );

      if (candidatesResult.isErr) {
        return Err(
          TmLookupException(
            'Failed to get candidates: ${candidatesResult.error}',
            sourceText,
            targetLanguageCode,
          ),
        );
      }

      final candidates = candidatesResult.value;
      if (candidates.isEmpty) {
        return Ok([]);
      }

      // Calculate similarity for each candidate
      final matches = <TmMatch>[];

      for (final candidate in candidates) {
        // Calculate combined similarity (returns SimilarityBreakdown directly, not Result)
        final score = _similarityCalculator.calculateSimilarity(
          text1: sourceText,
          text2: candidate.sourceText,
          category1: category,
          category2: null, // Note: Category is not stored in the database schema
        );

        // Filter by minimum similarity
        if (score.combinedScore < minSimilarity) {
          continue;
        }

        // Create match
        final match = TmMatch(
          entryId: candidate.id,
          sourceText: candidate.sourceText,
          targetText: candidate.translatedText,
          targetLanguageCode: targetLanguageCode,
          similarityScore: score.combinedScore,
          matchType: TmMatchType.fuzzy,
          breakdown: score,
          usageCount: candidate.usageCount,
          lastUsedAt:
              DateTime.fromMillisecondsSinceEpoch(candidate.lastUsedAt * 1000),
          qualityScore: candidate.qualityScore ?? AppConstants.defaultTmQuality,
          autoApplied: score.combinedScore >= AppConstants.autoAcceptTmThreshold,
        );

        matches.add(match);
      }

      // Sort by similarity (highest first)
      matches.sort((a, b) => b.similarityScore.compareTo(a.similarityScore));

      // Limit results
      final limitedMatches = matches.take(maxResults).toList();

      return Ok(limitedMatches);
    } catch (e, stackTrace) {
      return Err(
        TmLookupException(
          'Unexpected error finding fuzzy matches: ${e.toString()}',
          sourceText,
          targetLanguageCode,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Find fuzzy matches for multiple source texts in a batch using isolate.
  ///
  /// This method is optimized for bulk operations and runs similarity
  /// calculations in a background isolate to prevent UI freezing.
  ///
  /// Returns a map of source text to best match (or null if no match).
  Future<Result<Map<String, TmMatch?>, TmLookupException>> findFuzzyMatchesBatch({
    required List<String> sourceTexts,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    int maxResults = AppConstants.maxTmFuzzyResults,
    String? category,
  }) async {
    if (sourceTexts.isEmpty) {
      return Ok({});
    }

    try {
      // Resolve language code to database ID
      final targetLanguageId = await _resolveLanguageId(targetLanguageCode);
      if (targetLanguageId == null) {
        return Ok({for (final text in sourceTexts) text: null});
      }

      // Initialize isolate service
      final isolateService = IsolateSimilarityService.instance;
      await isolateService.initialize();

      final results = <String, TmMatch?>{};

      // Process each source text
      for (final sourceText in sourceTexts) {
        // Get candidates from repository (uses FTS5 for fast filtering)
        final candidatesResult = await _repository.findMatches(
          sourceText,
          targetLanguageId,
          minConfidence: minSimilarity - 0.1, // Get slightly more candidates for isolate filtering
        );

        if (candidatesResult.isErr || candidatesResult.value.isEmpty) {
          results[sourceText] = null;
          continue;
        }

        final candidates = candidatesResult.value;

        // Convert to isolate-compatible format
        final candidateData = candidates.map((c) => CandidateData(
          id: c.id,
          sourceText: c.sourceText,
          translatedText: c.translatedText,
          usageCount: c.usageCount,
          lastUsedAt: c.lastUsedAt,
          qualityScore: c.qualityScore ?? AppConstants.defaultTmQuality,
        )).toList();

        // Calculate similarity in isolate
        final similarityResults = await isolateService.calculateBatchSimilarity(
          sourceText: sourceText,
          candidates: candidateData,
          minSimilarity: minSimilarity,
          category: category,
        );

        if (similarityResults.isEmpty) {
          results[sourceText] = null;
          continue;
        }

        // Get the best match
        final bestResult = similarityResults.first;
        final bestCandidate = candidates.firstWhere((c) => c.id == bestResult.candidateId);

        final breakdown = SimilarityBreakdown(
          levenshteinScore: bestResult.levenshteinScore,
          jaroWinklerScore: bestResult.jaroWinklerScore,
          tokenScore: bestResult.tokenScore,
          contextBoost: bestResult.contextBoost,
          weights: const ScoreWeights(),
        );

        results[sourceText] = TmMatch(
          entryId: bestCandidate.id,
          sourceText: bestCandidate.sourceText,
          targetText: bestCandidate.translatedText,
          targetLanguageCode: targetLanguageCode,
          similarityScore: bestResult.combinedScore,
          matchType: TmMatchType.fuzzy,
          breakdown: breakdown,
          usageCount: bestCandidate.usageCount,
          lastUsedAt: DateTime.fromMillisecondsSinceEpoch(bestCandidate.lastUsedAt * 1000),
          qualityScore: bestCandidate.qualityScore ?? AppConstants.defaultTmQuality,
          autoApplied: bestResult.combinedScore >= AppConstants.autoAcceptTmThreshold,
        );
      }

      return Ok(results);
    } catch (e, stackTrace) {
      return Err(
        TmLookupException(
          'Unexpected error in batch fuzzy matching: ${e.toString()}',
          sourceTexts.firstOrNull ?? '',
          targetLanguageCode,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Find fuzzy matches using isolate for a single source text.
  ///
  /// This is more efficient than the regular findFuzzyMatches for heavy workloads
  /// as it runs similarity calculations in a background isolate.
  Future<Result<List<TmMatch>, TmLookupException>> findFuzzyMatchesIsolate({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    int maxResults = AppConstants.maxTmFuzzyResults,
    String? category,
  }) async {
    try {
      // Resolve language code to database ID
      final targetLanguageId = await _resolveLanguageId(targetLanguageCode);
      if (targetLanguageId == null) {
        return Ok([]);
      }

      // Get candidates from repository
      final candidatesResult = await _repository.findMatches(
        sourceText,
        targetLanguageId,
        minConfidence: minSimilarity - 0.1,
      );

      if (candidatesResult.isErr) {
        return Err(
          TmLookupException(
            'Failed to get candidates: ${candidatesResult.error}',
            sourceText,
            targetLanguageCode,
          ),
        );
      }

      final candidates = candidatesResult.value;
      if (candidates.isEmpty) {
        return Ok([]);
      }

      // Initialize isolate service and calculate similarity
      final isolateService = IsolateSimilarityService.instance;
      await isolateService.initialize();

      final candidateData = candidates.map((c) => CandidateData(
        id: c.id,
        sourceText: c.sourceText,
        translatedText: c.translatedText,
        usageCount: c.usageCount,
        lastUsedAt: c.lastUsedAt,
        qualityScore: c.qualityScore ?? AppConstants.defaultTmQuality,
      )).toList();

      final similarityResults = await isolateService.calculateBatchSimilarity(
        sourceText: sourceText,
        candidates: candidateData,
        minSimilarity: minSimilarity,
        category: category,
      );

      // Convert results to TmMatch objects
      final matches = <TmMatch>[];
      for (final result in similarityResults.take(maxResults)) {
        final candidate = candidates.firstWhere((c) => c.id == result.candidateId);

        final breakdown = SimilarityBreakdown(
          levenshteinScore: result.levenshteinScore,
          jaroWinklerScore: result.jaroWinklerScore,
          tokenScore: result.tokenScore,
          contextBoost: result.contextBoost,
          weights: const ScoreWeights(),
        );

        matches.add(TmMatch(
          entryId: candidate.id,
          sourceText: candidate.sourceText,
          targetText: candidate.translatedText,
          targetLanguageCode: targetLanguageCode,
          similarityScore: result.combinedScore,
          matchType: TmMatchType.fuzzy,
          breakdown: breakdown,
          usageCount: candidate.usageCount,
          lastUsedAt: DateTime.fromMillisecondsSinceEpoch(candidate.lastUsedAt * 1000),
          qualityScore: candidate.qualityScore ?? AppConstants.defaultTmQuality,
          autoApplied: result.combinedScore >= AppConstants.autoAcceptTmThreshold,
        ));
      }

      return Ok(matches);
    } catch (e, stackTrace) {
      return Err(
        TmLookupException(
          'Unexpected error in isolate fuzzy matching: ${e.toString()}',
          sourceText,
          targetLanguageCode,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  Future<Result<TmMatch?, TmLookupException>> findBestMatch({
    required String sourceText,
    required String targetLanguageCode,
    double minSimilarity = AppConstants.minTmSimilarity,
    String? category,
  }) async {
    try {
      // Try exact match first
      final exactResult = await findExactMatch(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
      );

      if (exactResult.isErr) {
        return Err(exactResult.error);
      }

      if (exactResult.value != null) {
        return Ok(exactResult.value);
      }

      // Fall back to fuzzy match
      final fuzzyResult = await findFuzzyMatches(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        minSimilarity: minSimilarity,
        maxResults: AppConstants.singleTmResult,
        category: category,
      );

      if (fuzzyResult.isErr) {
        return Err(fuzzyResult.error);
      }

      if (fuzzyResult.value.isEmpty) {
        return Ok(null);
      }

      return Ok(fuzzyResult.value.first);
    } catch (e, stackTrace) {
      return Err(
        TmLookupException(
          'Unexpected error finding best match: ${e.toString()}',
          sourceText,
          targetLanguageCode,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
