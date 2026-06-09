import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';

/// Regression test: entries written under [TmCache.generateExactMatchKey]
/// (the key space used by TmMatchingService.findExactMatch) must be reachable
/// by [TmCache.invalidateLanguagePair]. Previously the helpers built keys in a
/// different format (`<src>_<tgt>_<hash>`) than the writer (`<hash>:<tgt>`), so
/// invalidation silently matched nothing.
void main() {
  late TmCache cache;

  TmMatch sampleMatch() => TmMatch(
        entryId: 'e1',
        sourceText: 'hello',
        targetText: 'bonjour',
        targetLanguageCode: 'fr',
        similarityScore: 1.0,
        matchType: TmMatchType.exact,
        breakdown: const SimilarityBreakdown(
          levenshteinScore: 1.0,
          jaroWinklerScore: 1.0,
          tokenScore: 1.0,
          contextBoost: 0.0,
          weights: ScoreWeights.defaultWeights,
        ),
        usageCount: 1,
        lastUsedAt: DateTime(2024, 1, 1),
        autoApplied: true,
      );

  setUp(() {
    // TmCache is a singleton; clear shared state between tests.
    cache = TmCache();
    cache.clear();
  });

  test('generateExactMatchKey is the same string the writer would use', () {
    final key = TmCache.generateExactMatchKey(
      sourceHash: 'abc123',
      targetLanguageCode: 'FR',
    );
    // Hash first, colon separator, lowercased target — matches findExactMatch.
    expect(key, 'abc123:fr');
  });

  test('invalidateLanguagePair removes entries written via the canonical key',
      () {
    final key = TmCache.generateExactMatchKey(
      sourceHash: 'hash-1',
      targetLanguageCode: 'fr',
    );
    cache.putExactMatch(key, sampleMatch());
    expect(cache.getExactMatch(key), isNotNull);

    // Invalidate the language pair (source language is not part of the key).
    cache.invalidateLanguagePair('en', 'fr');

    expect(cache.getExactMatch(key), isNull,
        reason: 'entry must be reachable and removed by invalidateLanguagePair');
  });

  test('invalidateLanguagePair only removes the targeted language', () {
    final frKey = TmCache.generateExactMatchKey(
      sourceHash: 'hash-1',
      targetLanguageCode: 'fr',
    );
    final deKey = TmCache.generateExactMatchKey(
      sourceHash: 'hash-1',
      targetLanguageCode: 'de',
    );
    cache.putExactMatch(frKey, sampleMatch());
    cache.putExactMatch(deKey, sampleMatch());

    cache.invalidateLanguagePair('en', 'fr');

    expect(cache.getExactMatch(frKey), isNull);
    expect(cache.getExactMatch(deKey), isNotNull,
        reason: 'unrelated target language must be untouched');
  });
}
