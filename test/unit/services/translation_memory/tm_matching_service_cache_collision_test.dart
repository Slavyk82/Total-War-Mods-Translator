import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/tm_matching_service.dart';

// Regression tests for the exact-match anti-collision guard vs the cache.
//
// The cache key is `<aggressiveHash>:<target>`, and the aggressive normalizer
// lowercases and strips markup/punctuation — so distinct Total War sources
// such as `Attack` and `ATTACK` share ONE cache slot. The collision verdict
// (true exact vs downgraded fuzzy) is therefore PER-REQUEST and must be
// recomputed on every lookup, cache hit included. Previously the guard only
// ran on a cache miss: a cached `autoApplied: true` exact for `Attack` was
// returned verbatim for `ATTACK` (silently auto-applying the wrong-case
// translation), and conversely a cached downgrade poisoned true exacts.

class _MockTmRepository extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

void main() {
  late _MockTmRepository tmRepository;
  late _MockLanguageRepository languageRepository;
  late TmCache cache;
  late TmMatchingService service;

  const targetLanguage = Language(
    id: 'lang-fr',
    code: 'fr',
    name: 'French',
    nativeName: 'Français',
  );

  final storedEntry = TranslationMemoryEntry(
    id: 'entry-attack',
    sourceText: 'Attack',
    sourceHash: 'unused-by-stub',
    sourceLanguageId: 'lang-en',
    targetLanguageId: 'lang-fr',
    translatedText: 'Attaque',
    usageCount: 3,
    createdAt: 1000,
    lastUsedAt: 1000,
    updatedAt: 1000,
  );

  setUp(() {
    tmRepository = _MockTmRepository();
    languageRepository = _MockLanguageRepository();
    // TmCache is a process-wide singleton: clear shared state between tests.
    cache = TmCache();
    cache.clear();

    when(() => languageRepository.getByCode('fr'))
        .thenAnswer((_) async => const Ok(targetLanguage));
    // `Attack` and `ATTACK` aggressive-normalize to the same hash, so both
    // lookups resolve to the same stored entry.
    when(() => tmRepository.findByHash(any(), any()))
        .thenAnswer((_) async => Ok(storedEntry));

    service = TmMatchingService(
      repository: tmRepository,
      languageRepository: languageRepository,
      normalizer: TextNormalizer(),
      similarityCalculator: SimilarityCalculator(),
      cache: cache,
    );
  });

  group('TmMatchingService.findExactMatch — collision guard on cache hit', () {
    test(
        'a cached true-exact for `Attack` must NOT be returned as auto-applied '
        'exact for `ATTACK` (per-request re-verification on cache hit)',
        () async {
      // 1st lookup: true exact, populates the cache.
      final first = await service.findExactMatch(
        sourceText: 'Attack',
        targetLanguageCode: 'fr',
      );
      expect(first.isOk, isTrue, reason: first.toString());
      final firstMatch = first.unwrap();
      expect(firstMatch, isNotNull);
      expect(firstMatch!.matchType, TmMatchType.exact);
      expect(firstMatch.autoApplied, isTrue);

      // 2nd lookup with different case hits the SAME cache slot. The guard
      // must re-run: case differs → downgrade, never auto-apply.
      final second = await service.findExactMatch(
        sourceText: 'ATTACK',
        targetLanguageCode: 'fr',
      );
      expect(second.isOk, isTrue, reason: second.toString());
      final secondMatch = second.unwrap();
      expect(secondMatch, isNotNull);
      expect(secondMatch!.matchType, TmMatchType.fuzzy,
          reason: 'case-only collision must be downgraded to fuzzy');
      expect(secondMatch.autoApplied, isFalse,
          reason: 'a collision must never be silently auto-applied');

      // The cache must still serve the second lookup (no second DB roundtrip):
      // the fix is re-verification, not cache bypass.
      verify(() => tmRepository.findByHash(any(), any())).called(1);
    });

    test(
        'a cached downgrade for `ATTACK` must NOT poison a subsequent '
        'true-exact lookup for `Attack`', () async {
      // 1st lookup: collision (requested ATTACK, stored Attack) → downgraded.
      final first = await service.findExactMatch(
        sourceText: 'ATTACK',
        targetLanguageCode: 'fr',
      );
      expect(first.isOk, isTrue, reason: first.toString());
      expect(first.unwrap()!.matchType, TmMatchType.fuzzy);
      expect(first.unwrap()!.autoApplied, isFalse);

      // 2nd lookup is byte-exact with the stored entry: must come back as a
      // genuine exact match even though the cache slot holds a downgrade.
      final second = await service.findExactMatch(
        sourceText: 'Attack',
        targetLanguageCode: 'fr',
      );
      expect(second.isOk, isTrue, reason: second.toString());
      final secondMatch = second.unwrap();
      expect(secondMatch, isNotNull);
      expect(secondMatch!.matchType, TmMatchType.exact,
          reason: 'true exact must not inherit a cached downgrade');
      expect(secondMatch.autoApplied, isTrue);
      expect(secondMatch.targetText, 'Attaque');
    });
  });
}
