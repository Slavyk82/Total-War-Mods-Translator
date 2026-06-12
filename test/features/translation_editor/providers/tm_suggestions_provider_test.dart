import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/providers/tm_suggestions_provider.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';
import 'package:twmt/services/translation_memory/models/tm_match.dart';

class _MockUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockTmService extends Mock implements ITranslationMemoryService {}

/// Only entryId + similarityScore are read by the provider; a Fake sidesteps
/// building a full TmMatch (SimilarityBreakdown + ScoreWeights).
class _FakeMatch extends Fake implements TmMatch {
  _FakeMatch(this._id, this._score);
  final String _id;
  final double _score;
  @override
  String get entryId => _id;
  @override
  double get similarityScore => _score;
}

const _unit = TranslationUnit(
  id: 'u-1',
  projectId: 'p-1',
  key: 'greeting',
  sourceText: 'Hello',
  createdAt: 0,
  updatedAt: 0,
);

void main() {
  late _MockUnitRepo unitRepo;
  late _MockTmService tmService;

  setUp(() {
    unitRepo = _MockUnitRepo();
    tmService = _MockTmService();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        translationUnitRepositoryProvider.overrideWithValue(unitRepo),
        translationMemoryServiceProvider.overrideWithValue(tmService),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('throws when the translation unit cannot be loaded', () async {
    when(() => unitRepo.getById('u-1')).thenAnswer(
      (_) async => const Err<TranslationUnit, TWMTDatabaseException>(
        TWMTDatabaseException('not found'),
      ),
    );

    final container = makeContainer();
    // `.future` hangs (StateError "disposed during loading") for an autoDispose
    // provider whose build throws on the first microtask; assert via the
    // AsyncValue after pumping instead (see provider-test-patterns memory).
    final provider = tmSuggestionsForUnitProvider('u-1', 'en', 'fr');
    container.listen(provider, (_, _) {});
    await pumpEventQueue();

    expect(container.read(provider).hasError, isTrue);
  });

  test('merges exact + fuzzy matches, dedupes and sorts by similarity',
      () async {
    when(() => unitRepo.getById('u-1')).thenAnswer(
      (_) async => const Ok<TranslationUnit, TWMTDatabaseException>(_unit),
    );
    when(() => tmService.findExactMatch(
          sourceText: 'Hello',
          targetLanguageCode: 'fr',
        )).thenAnswer(
      (_) async => Ok<TmMatch?, TmLookupException>(_FakeMatch('e1', 1.0)),
    );
    when(() => tmService.findFuzzyMatches(
          sourceText: 'Hello',
          targetLanguageCode: 'fr',
          minSimilarity: any(named: 'minSimilarity'),
          maxResults: any(named: 'maxResults'),
        )).thenAnswer(
      (_) async => Ok<List<TmMatch>, TmLookupException>([
        _FakeMatch('e1', 1.0), // duplicate of the exact match -> dropped
        _FakeMatch('e2', 0.8),
        _FakeMatch('e3', 0.9),
      ]),
    );

    final container = makeContainer();
    final matches = await container
        .read(tmSuggestionsForUnitProvider('u-1', 'en', 'fr').future);

    expect(matches.map((m) => m.entryId), ['e1', 'e3', 'e2']);
  });

  test('returns only the exact match when fuzzy lookup fails', () async {
    when(() => unitRepo.getById('u-1')).thenAnswer(
      (_) async => const Ok<TranslationUnit, TWMTDatabaseException>(_unit),
    );
    when(() => tmService.findExactMatch(
          sourceText: any(named: 'sourceText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer(
      (_) async => Ok<TmMatch?, TmLookupException>(_FakeMatch('e1', 1.0)),
    );
    when(() => tmService.findFuzzyMatches(
          sourceText: any(named: 'sourceText'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          minSimilarity: any(named: 'minSimilarity'),
          maxResults: any(named: 'maxResults'),
        )).thenAnswer(
      (_) async => Err<List<TmMatch>, TmLookupException>(
        const TmLookupException('boom', 'Hello', 'fr'),
      ),
    );

    final container = makeContainer();
    final matches = await container
        .read(tmSuggestionsForUnitProvider('u-1', 'en', 'fr').future);

    expect(matches.map((m) => m.entryId), ['e1']);
  });
}
