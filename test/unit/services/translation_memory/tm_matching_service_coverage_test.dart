import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/tm_matching_service.dart';

class _MockTmRepo extends Mock implements TranslationMemoryRepository {}

class _MockLangRepo extends Mock implements LanguageRepository {}

class _MockNormalizer extends Mock implements TextNormalizer {}

class _MockSimilarity extends Mock implements SimilarityCalculator {}

class _MockCache extends Mock implements TmCache {}

TranslationMemoryEntry _entry(
  String id,
  String source,
  String translated, {
  int usageCount = 0,
}) =>
    TranslationMemoryEntry(
      id: id,
      sourceText: source,
      sourceHash: 'hash-$id',
      sourceLanguageId: 'en-id',
      targetLanguageId: 'fr-id',
      translatedText: translated,
      usageCount: usageCount,
      createdAt: 0,
      lastUsedAt: 0,
      updatedAt: 0,
    );

/// Breakdown whose combinedScore == [score] (weights sum to 1, no boost).
SimilarityBreakdown _breakdown(double score) => SimilarityBreakdown(
      levenshteinScore: score,
      jaroWinklerScore: score,
      tokenScore: score,
      contextBoost: 0,
      weights: const ScoreWeights(),
    );

TmMatch _match(String id, double score) => TmMatch(
      entryId: id,
      sourceText: 's',
      targetText: 't',
      targetLanguageCode: 'fr',
      similarityScore: score,
      matchType: TmMatchType.exact,
      breakdown: _breakdown(score),
      usageCount: 0,
      lastUsedAt: DateTime(2026, 1, 1),
      autoApplied: true,
    );

Future<Result<Language, TWMTDatabaseException>> _errLang() async =>
    Err(TWMTDatabaseException('no language'));

Future<Result<TranslationMemoryEntry, TWMTDatabaseException>>
    _errEntry() async => Err(TWMTDatabaseException('not found'));

void main() {
  setUpAll(() {
    registerFallbackValue(_match('f', 1));
  });

  late _MockTmRepo repo;
  late _MockLangRepo langRepo;
  late _MockNormalizer normalizer;
  late _MockSimilarity similarity;
  late _MockCache cache;
  late TmMatchingService service;

  setUp(() {
    repo = _MockTmRepo();
    langRepo = _MockLangRepo();
    normalizer = _MockNormalizer();
    similarity = _MockSimilarity();
    cache = _MockCache();
    service = TmMatchingService(
      repository: repo,
      languageRepository: langRepo,
      normalizer: normalizer,
      similarityCalculator: similarity,
      cache: cache,
    );

    when(() => normalizer.normalize(any())).thenReturn('normalized');
    when(() => cache.getExactMatch(any())).thenReturn(null);
    when(() => cache.putExactMatch(any(), any())).thenReturn(null);
    when(() => langRepo.getByCode('fr')).thenAnswer(
      (_) async => Ok(
        const Language(
            id: 'fr-id', code: 'fr', name: 'French', nativeName: 'Français'),
      ),
    );
  });

  group('findExactMatch — cache and language-id caching', () {
    test('a true-exact cache hit is re-verified and returned without DB lookup',
        () async {
      // Cached entry is byte-exact with the requested source.
      when(() => cache.getExactMatch(any())).thenReturn(
        TmMatch(
          entryId: 'cached',
          sourceText: 'Hello',
          targetText: 'Bonjour',
          targetLanguageCode: 'fr',
          similarityScore: 1,
          matchType: TmMatchType.exact,
          breakdown: _breakdown(1),
          usageCount: 3,
          lastUsedAt: DateTime(2026, 1, 1),
          autoApplied: true,
        ),
      );

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      final match = r.unwrap()!;
      expect(match.entryId, 'cached');
      expect(match.matchType, TmMatchType.exact);
      expect(match.autoApplied, isTrue);
      // Cache hit short-circuits the repository.
      verifyNever(() => repo.findByHash(any(), any()));
    });

    test('a cache hit that is a case collision is downgraded per-request',
        () async {
      // Cached stored source differs only by case from the request.
      when(() => cache.getExactMatch(any())).thenReturn(
        TmMatch(
          entryId: 'cached',
          sourceText: 'HELLO',
          targetText: 'BONJOUR',
          targetLanguageCode: 'fr',
          similarityScore: 1,
          matchType: TmMatchType.exact,
          breakdown: _breakdown(1),
          usageCount: 0,
          lastUsedAt: DateTime(2026, 1, 1),
          autoApplied: true,
        ),
      );
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: any(named: 'text2'),
          )).thenReturn(_breakdown(0.9));

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      final match = r.unwrap()!;
      expect(match.matchType, TmMatchType.fuzzy);
      expect(match.autoApplied, isFalse);
      verifyNever(() => repo.findByHash(any(), any()));
    });

    test('caches the resolved language id across calls (single DB lookup)',
        () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => _errEntry());

      await service.findExactMatch(
          sourceText: 'one', targetLanguageCode: 'fr');
      await service.findExactMatch(
          sourceText: 'two', targetLanguageCode: 'fr');

      // Language resolved once, then served from the in-memory map.
      verify(() => langRepo.getByCode('fr')).called(1);
    });

    test('caps a not-found exact lookup result (null) into the cache',
        () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => _errEntry());

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      expect(r.unwrap(), isNull);
      verify(() => cache.putExactMatch(any(), null)).called(1);
    });

    test('wraps an unexpected error into a TmLookupException', () async {
      when(() => normalizer.normalize(any())).thenThrow(StateError('boom'));

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Unexpected error finding exact'));
    });
  });

  group('findFuzzyMatches — error/edge branches', () {
    test('returns empty when the target language cannot be resolved', () async {
      when(() => langRepo.getByCode('zz'))
          .thenAnswer((_) async => _errLang());

      final r = await service.findFuzzyMatches(
          sourceText: 'Hi', targetLanguageCode: 'zz');

      expect(r.unwrap(), isEmpty);
      verifyNever(() => repo.findMatches(any(), any(),
          minConfidence: any(named: 'minConfidence')));
    });

    test('propagates a repository error while fetching candidates', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db down')));

      final r = await service.findFuzzyMatches(
          sourceText: 'Hi', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Failed to get candidates'));
    });

    test('wraps an unexpected error into a TmLookupException', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok([_entry('e', 'a', 'b')]));
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: any(named: 'text2'),
            category1: any(named: 'category1'),
            category2: any(named: 'category2'),
          )).thenThrow(StateError('boom'));

      final r = await service.findFuzzyMatches(
          sourceText: 'Hi', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Unexpected error finding fuzzy'));
    });
  });

  group('findBestMatch — error propagation', () {
    test('returns the exact-match error when the exact lookup fails', () async {
      // Force an exception inside findExactMatch via the normalizer.
      when(() => normalizer.normalize(any())).thenThrow(StateError('boom'));

      final r = await service.findBestMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Unexpected error finding exact'));
      verifyNever(() => repo.findMatches(any(), any(),
          minConfidence: any(named: 'minConfidence')));
    });

    test('returns the fuzzy-match error when the fuzzy fallback fails',
        () async {
      // No exact match, then a candidate-fetch error in the fuzzy fallback.
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => _errEntry());
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db down')));

      final r = await service.findBestMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Failed to get candidates'));
    });
  });

  group('findFuzzyMatchesBatch — isolate path', () {
    test('returns an empty map for empty input without resolving language',
        () async {
      final r = await service.findFuzzyMatchesBatch(
          sourceTexts: const [], targetLanguageCode: 'fr');

      expect(r.unwrap(), isEmpty);
      verifyNever(() => langRepo.getByCode(any()));
    });

    test('maps every text to null when the language cannot be resolved',
        () async {
      when(() => langRepo.getByCode('zz'))
          .thenAnswer((_) async => _errLang());

      final r = await service.findFuzzyMatchesBatch(
          sourceTexts: const ['a', 'b'], targetLanguageCode: 'zz');

      final map = r.unwrap();
      expect(map, {'a': null, 'b': null});
    });

    test('maps a text to null on a candidate-fetch error or empty candidates',
        () async {
      when(() => repo.findMatches('errText', any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db down')));
      when(() => repo.findMatches('emptyText', any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok(<TranslationMemoryEntry>[]));

      final r = await service.findFuzzyMatchesBatch(
        sourceTexts: const ['errText', 'emptyText'],
        targetLanguageCode: 'fr',
      );

      final map = r.unwrap();
      expect(map['errText'], isNull);
      expect(map['emptyText'], isNull);
    });

    test('computes a best match in the isolate for a strong candidate',
        () async {
      // Identical source -> the real isolate computes ~1.0 combined score.
      when(() => repo.findMatches('Hello world', any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok([
                _entry('cand', 'Hello world', 'Bonjour le monde'),
              ]));

      final r = await service.findFuzzyMatchesBatch(
        sourceTexts: const ['Hello world'],
        targetLanguageCode: 'fr',
      );

      final map = r.unwrap();
      final match = map['Hello world'];
      expect(match, isNotNull);
      expect(match!.entryId, 'cand');
      expect(match.matchType, TmMatchType.fuzzy);
      expect(match.similarityScore, greaterThanOrEqualTo(0.99));
      expect(match.autoApplied, isTrue);
      expect(match.targetText, 'Bonjour le monde');
    });

    test('maps a text to null when no candidate clears minSimilarity',
        () async {
      // A wildly different candidate -> isolate filters it out below threshold.
      when(() => repo.findMatches('Hello world', any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok([
                _entry('cand', 'zzz qqq xxx', 'unrelated'),
              ]));

      final r = await service.findFuzzyMatchesBatch(
        sourceTexts: const ['Hello world'],
        targetLanguageCode: 'fr',
      );

      expect(r.unwrap()['Hello world'], isNull);
    });

    test('wraps an unexpected error into a TmLookupException', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenThrow(StateError('boom'));

      final r = await service.findFuzzyMatchesBatch(
        sourceTexts: const ['Hello'],
        targetLanguageCode: 'fr',
      );

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Unexpected error in batch fuzzy'));
    });
  });

  group('findFuzzyMatchesIsolate — isolate path', () {
    test('returns empty when the language cannot be resolved', () async {
      when(() => langRepo.getByCode('zz'))
          .thenAnswer((_) async => _errLang());

      final r = await service.findFuzzyMatchesIsolate(
          sourceText: 'Hi', targetLanguageCode: 'zz');

      expect(r.unwrap(), isEmpty);
    });

    test('propagates a candidate-fetch error', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db down')));

      final r = await service.findFuzzyMatchesIsolate(
          sourceText: 'Hi', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Failed to get candidates'));
    });

    test('returns empty when there are no candidates', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok(<TranslationMemoryEntry>[]));

      final r = await service.findFuzzyMatchesIsolate(
          sourceText: 'Hi', targetLanguageCode: 'fr');

      expect(r.unwrap(), isEmpty);
    });

    test('computes ranked matches in the isolate and limits results',
        () async {
      // Two candidates: one identical (strong), one weak; maxResults limits.
      when(() => repo.findMatches('Hello world', any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok([
                _entry('strong', 'Hello world', 'fort'),
                _entry('weak', 'Hello there world friend', 'faible'),
              ]));

      final r = await service.findFuzzyMatchesIsolate(
        sourceText: 'Hello world',
        targetLanguageCode: 'fr',
        minSimilarity: 0.1,
        maxResults: 1,
      );

      final matches = r.unwrap();
      expect(matches, hasLength(1));
      // Highest score first: the identical source.
      expect(matches.first.entryId, 'strong');
      expect(matches.first.similarityScore, greaterThanOrEqualTo(0.99));
      expect(matches.first.autoApplied, isTrue);
    });

    test('wraps an unexpected error into a TmLookupException', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenThrow(StateError('boom'));

      final r = await service.findFuzzyMatchesIsolate(
          sourceText: 'Hi', targetLanguageCode: 'fr');

      expect(r.isErr, isTrue);
      expect(r.error.toString(), contains('Unexpected error in isolate fuzzy'));
    });
  });
}
