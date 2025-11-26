import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';

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
      // Calculate source hash (using normalized text)
      final normalized = _normalizer.normalize(sourceText);
      final sourceHash = normalized.hashCode.toString();

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
