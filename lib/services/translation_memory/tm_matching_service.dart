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

  /// Conservative normalization for verifying a *true* exact match.
  ///
  /// Unlike [TextNormalizer.normalize] (which lowercases, strips markup and
  /// normalizes punctuation — all of which are SIGNIFICANT for Total War text
  /// like `Attack` vs `ATTACK` or `[[col:...]]` markup), this preserves case,
  /// markup and punctuation. It only applies Unicode NFC composition and trims
  /// trailing whitespace, so two strings that differ solely by trailing
  /// whitespace still count as exact.
  ///
  /// NOTE: This is intentionally NOT used to compute the lookup hash. The
  /// write-side hash (in tm_crud_service.dart, tmx_service.dart and
  /// tm_maintenance_service.dart) is computed from the aggressive
  /// [TextNormalizer.normalize], so the read-side lookup hash must keep using
  /// that same aggressive normalization to hit the index. This helper is used
  /// only to *verify*, after a hash hit, that the stored source is genuinely
  /// the same string and not merely a case/markup/punctuation collision.
  static String conservativeExactNormalize(String text) {
    // Dart String is UTF-16; there is no built-in NFC compositor in the SDK and
    // the project's TextNormalizer treats NFC as a no-op, so we mirror that
    // behavior here and only trim trailing whitespace while preserving case,
    // markup and punctuation.
    return text.replaceAll(RegExp(r'\s+$'), '');
  }

  /// Resolve language code to database ID (with caching)
  /// Note: Language codes are normalized to lowercase for consistent lookup
  Future<String?> _resolveLanguageId(String languageCode) async {
    // Normalize to lowercase for consistent lookup
    // (TranslationContext uses uppercase for DeepL API, but DB stores lowercase)
    final normalizedCode = languageCode.toLowerCase();

    if (_languageCodeToId.containsKey(normalizedCode)) {
      return _languageCodeToId[normalizedCode];
    }

    final result = await _languageRepository.getByCode(normalizedCode);
    if (result.isOk) {
      final languageId = result.unwrap().id;
      _languageCodeToId[normalizedCode] = languageId;
      return languageId;
    }
    return null;
  }

  /// GUARD AGAINST HASH COLLISIONS FROM AGGRESSIVE NORMALIZATION.
  ///
  /// The lookup hash is derived from the aggressive normalizer (lowercase,
  /// remove markup, normalize punctuation) so it can match the write-side
  /// hash. That means distinct Total War sources such as `Attack` vs
  /// `ATTACK`, or strings differing only by `[[col:...]]` markup, collide on
  /// the same hash. For Total War text these differences ARE significant, so
  /// we must NOT treat such a collision as a verbatim, auto-applied 100%
  /// match (which would be written as status=translated).
  ///
  /// Verifies the stored source is byte-exact (after only conservative,
  /// case/markup/punctuation-PRESERVING normalization) against the REQUESTED
  /// [sourceText]. If it is, builds a true exact match. If it differs,
  /// downgrades to a fuzzy match that needs review (autoApplied=false) so the
  /// wrong translation is never silently applied.
  ///
  /// MUST run per request — including on cache hits and preloaded entries —
  /// because the verdict depends on the requested text, not on the entry.
  TmMatch _verifyMatchForRequest({
    required String sourceText,
    required String targetLanguageCode,
    required String entryId,
    required String storedSourceText,
    required String storedTargetText,
    required int usageCount,
    required DateTime lastUsedAt,
  }) {
    final requestedConservative = conservativeExactNormalize(sourceText);
    final storedConservative = conservativeExactNormalize(storedSourceText);
    final isTrueExact = requestedConservative == storedConservative;

    if (isTrueExact) {
      // Create TmMatch with 100% similarity
      final breakdown = SimilarityBreakdown(
        levenshteinScore: AppConstants.exactMatchSimilarity,
        jaroWinklerScore: AppConstants.exactMatchSimilarity,
        tokenScore: AppConstants.exactMatchSimilarity,
        contextBoost: AppConstants.zeroSimilarity,
        weights: const ScoreWeights(),
      );

      return TmMatch(
        entryId: entryId,
        sourceText: storedSourceText,
        targetText: storedTargetText,
        targetLanguageCode: targetLanguageCode,
        similarityScore: AppConstants.exactMatchSimilarity,
        matchType: TmMatchType.exact,
        breakdown: breakdown,
        usageCount: usageCount,
        lastUsedAt: lastUsedAt,
        autoApplied: true,
      );
    }

    // Normalization-only collision: compute the real similarity so the
    // user sees an honest score, and never auto-apply it.
    final score = _similarityCalculator.calculateSimilarity(
      text1: sourceText,
      text2: storedSourceText,
    );

    return TmMatch(
      entryId: entryId,
      sourceText: storedSourceText,
      targetText: storedTargetText,
      targetLanguageCode: targetLanguageCode,
      similarityScore: score.combinedScore,
      matchType: TmMatchType.fuzzy,
      breakdown: score,
      usageCount: usageCount,
      lastUsedAt: lastUsedAt,
      // Force manual review: a case/markup/punctuation difference in Total
      // War text must never be auto-applied, regardless of the numeric
      // similarity score.
      autoApplied: false,
    );
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

      // Build cache key via the canonical generator so writes share the same
      // key space as TmCache.invalidateLanguagePair / preloadEntries.
      final cacheKey = TmCache.generateExactMatchKey(
        sourceHash: sourceHash,
        targetLanguageCode: targetLanguageCode,
      );

      // Check cache first. The cache key is the AGGRESSIVE hash, so distinct
      // sources like `Attack` and `ATTACK` share one slot: the cached value
      // only tells us which TM entry the hash resolves to. The exact-vs-
      // collision verdict is per-request and is re-derived below on every
      // lookup — returning a cached match verbatim would either auto-apply a
      // wrong-case translation or let a cached downgrade poison true exacts.
      final cached = _cache.getExactMatch(cacheKey);
      if (cached != null) {
        return Ok(_verifyMatchForRequest(
          sourceText: sourceText,
          targetLanguageCode: targetLanguageCode,
          entryId: cached.entryId,
          storedSourceText: cached.sourceText,
          storedTargetText: cached.targetText,
          usageCount: cached.usageCount,
          lastUsedAt: cached.lastUsedAt,
        ));
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

      final match = _verifyMatchForRequest(
        sourceText: sourceText,
        targetLanguageCode: targetLanguageCode,
        entryId: entry.id,
        storedSourceText: entry.sourceText,
        storedTargetText: entry.translatedText,
        usageCount: entry.usageCount,
        lastUsedAt:
            DateTime.fromMillisecondsSinceEpoch(entry.lastUsedAt * 1000),
      );

      // Cache the result. Whatever form is cached (exact or downgraded), the
      // cache-hit path above re-verifies against the next request's source.
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

      // Widen the repository prefilter below minSimilarity. findMatches
      // pre-filters on Levenshtein similarity ALONE, but the authoritative
      // cutoff below (score.combinedScore < minSimilarity) uses the combined
      // 3-algorithm score. A candidate whose combined score clears the
      // threshold but whose Levenshtein component is lower would otherwise be
      // dropped here and never scored. Mirrors the isolate paths.
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
