import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/translation_memory_entry.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/similarity_calculator.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tm_cache.dart';
import 'package:twmt/services/translation_memory/tm_matching_service.dart';

// Regression test: findFuzzyMatches passed minConfidence == minSimilarity into
// the repository, whose FTS prefilter uses LEVENSHTEIN ONLY. A candidate whose
// COMBINED 3-algorithm score clears the threshold but whose Levenshtein
// component alone is below it was dropped at the prefilter and never scored.
// The isolate paths deliberately widen the net with `minSimilarity - 0.1`; the
// synchronous path (used by findBestMatch) must do the same so it does not
// return fewer matches than the isolate path for identical input.

class _MockTmRepository extends Mock implements TranslationMemoryRepository {}

class _MockLanguageRepository extends Mock implements LanguageRepository {}

void main() {
  late _MockTmRepository tmRepository;
  late _MockLanguageRepository languageRepository;
  late TmMatchingService service;

  const targetLanguage = Language(
    id: 'lang-fr',
    code: 'fr',
    name: 'French',
    nativeName: 'Français',
  );

  setUp(() {
    tmRepository = _MockTmRepository();
    languageRepository = _MockLanguageRepository();
    TmCache().clear();

    when(() => languageRepository.getByCode('fr'))
        .thenAnswer((_) async => const Ok(targetLanguage));
    when(() => tmRepository.findMatches(
          any(),
          any(),
          minConfidence: any(named: 'minConfidence'),
        )).thenAnswer((_) async => Ok(<TranslationMemoryEntry>[]));

    service = TmMatchingService(
      repository: tmRepository,
      languageRepository: languageRepository,
      normalizer: TextNormalizer(),
      similarityCalculator: SimilarityCalculator(),
      cache: TmCache(),
    );
  });

  test('widens the repository prefilter by 0.1 below minSimilarity, matching '
      'the isolate paths', () async {
    await service.findFuzzyMatches(
      sourceText: 'cavalry charge',
      targetLanguageCode: 'fr',
      minSimilarity: 0.85,
    );

    final captured = verify(() => tmRepository.findMatches(
          any(),
          any(),
          minConfidence: captureAny(named: 'minConfidence'),
        )).captured;
    expect(
      captured.single as double,
      closeTo(0.75, 1e-9),
      reason: 'the Levenshtein-only prefilter must be widened so combined-score '
          'matches are not dropped before the authoritative combined-score cut',
    );
  });
}
