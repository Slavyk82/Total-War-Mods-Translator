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

void main() {
  setUpAll(() {
    registerFallbackValue(
      TmMatch(
        entryId: 'f',
        sourceText: 'f',
        targetText: 'f',
        targetLanguageCode: 'fr',
        similarityScore: 1,
        matchType: TmMatchType.exact,
        breakdown: _breakdown(1),
        usageCount: 0,
        lastUsedAt: DateTime(2026, 1, 1),
        autoApplied: true,
      ),
    );
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
    when(() => langRepo.getByCode('fr')).thenAnswer((_) async => Ok(
          const Language(id: 'fr-id', code: 'fr', name: 'French', nativeName: 'Français'),
        ));
  });

  group('conservativeExactNormalize', () {
    test('trims trailing whitespace but preserves case and markup', () {
      expect(TmMatchingService.conservativeExactNormalize('Attack   '), 'Attack');
      expect(
        TmMatchingService.conservativeExactNormalize('[[col:red]]Hi'),
        '[[col:red]]Hi',
      );
    });
  });

  group('findExactMatch', () {
    test('returns null when the target language cannot be resolved', () async {
      when(() => langRepo.getByCode('zz'))
          .thenAnswer((_) async => _errLang());

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'zz');

      expect(r.unwrap(), isNull);
      verifyNever(() => repo.findByHash(any(), any()));
    });

    test('returns null when no entry is stored for the hash', () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => _errEntry());

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      expect(r.unwrap(), isNull);
    });

    test('a byte-exact stored source yields an auto-applied exact match',
        () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => Ok(_entry('e1', 'Hello', 'Bonjour')));

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      final match = r.unwrap()!;
      expect(match.matchType, TmMatchType.exact);
      expect(match.autoApplied, isTrue);
      expect(match.targetText, 'Bonjour');
    });

    test('a case-only collision downgrades to a non-applied fuzzy match',
        () async {
      // Requested 'Hello' but stored 'HELLO' share the aggressive hash.
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => Ok(_entry('e1', 'HELLO', 'BONJOUR')));
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: any(named: 'text2'),
          )).thenReturn(_breakdown(0.9));

      final r = await service.findExactMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      final match = r.unwrap()!;
      expect(match.matchType, TmMatchType.fuzzy);
      expect(match.autoApplied, isFalse);
    });
  });

  group('findFuzzyMatches', () {
    test('rejects an out-of-range minSimilarity', () async {
      final r = await service.findFuzzyMatches(
          sourceText: 'Hi', targetLanguageCode: 'fr', minSimilarity: 1.5);
      expect(r.isErr, isTrue);
    });

    test('rejects a non-positive maxResults', () async {
      final r = await service.findFuzzyMatches(
          sourceText: 'Hi', targetLanguageCode: 'fr', maxResults: 0);
      expect(r.isErr, isTrue);
    });

    test('returns empty when there are no candidates', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok(<TranslationMemoryEntry>[]));

      final r = await service.findFuzzyMatches(
          sourceText: 'Hi', targetLanguageCode: 'fr');
      expect(r.unwrap(), isEmpty);
    });

    test('filters below threshold, sorts desc, and limits results', () async {
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok([
                _entry('low', 'low', 'l'),
                _entry('high', 'high', 'h'),
                _entry('mid', 'mid', 'm'),
              ]));
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: 'low',
            category1: any(named: 'category1'),
            category2: any(named: 'category2'),
          )).thenReturn(_breakdown(0.50)); // below 0.85 -> dropped
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: 'high',
            category1: any(named: 'category1'),
            category2: any(named: 'category2'),
          )).thenReturn(_breakdown(0.98));
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: 'mid',
            category1: any(named: 'category1'),
            category2: any(named: 'category2'),
          )).thenReturn(_breakdown(0.90));

      final r = await service.findFuzzyMatches(
          sourceText: 'q', targetLanguageCode: 'fr', maxResults: 5);

      final matches = r.unwrap();
      expect(matches.map((m) => m.entryId), ['high', 'mid']); // sorted, 'low' dropped
      expect(matches.first.autoApplied, isTrue); // 0.98 >= autoAccept
    });
  });

  group('findBestMatch', () {
    test('prefers an exact match when one exists', () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => Ok(_entry('e1', 'Hello', 'Bonjour')));

      final r = await service.findBestMatch(
          sourceText: 'Hello', targetLanguageCode: 'fr');

      expect(r.unwrap()!.matchType, TmMatchType.exact);
      verifyNever(() => repo.findMatches(any(), any(),
          minConfidence: any(named: 'minConfidence')));
    });

    test('falls back to the top fuzzy match when no exact match exists',
        () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => _errEntry());
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok([_entry('f1', 'fuzzy', 't')]));
      when(() => similarity.calculateSimilarity(
            text1: any(named: 'text1'),
            text2: any(named: 'text2'),
            category1: any(named: 'category1'),
            category2: any(named: 'category2'),
          )).thenReturn(_breakdown(0.90));

      final r = await service.findBestMatch(
          sourceText: 'fuzzy', targetLanguageCode: 'fr');

      expect(r.unwrap()!.entryId, 'f1');
    });

    test('returns null when neither exact nor fuzzy matches exist', () async {
      when(() => repo.findByHash(any(), any()))
          .thenAnswer((_) async => _errEntry());
      when(() => repo.findMatches(any(), any(),
              minConfidence: any(named: 'minConfidence')))
          .thenAnswer((_) async => Ok(<TranslationMemoryEntry>[]));

      final r = await service.findBestMatch(
          sourceText: 'nope', targetLanguageCode: 'fr');

      expect(r.unwrap(), isNull);
    });
  });
}

Future<Result<Language, TWMTDatabaseException>> _errLang() async =>
    Err(TWMTDatabaseException('no language'));

Future<Result<TranslationMemoryEntry, TWMTDatabaseException>> _errEntry() async =>
    Err(TWMTDatabaseException('not found'));
