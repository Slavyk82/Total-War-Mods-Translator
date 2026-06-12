import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_filter_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_term_with_variants.dart';

class MockGlossaryRepository extends Mock implements GlossaryRepository {}

Glossary _glossary({
  String id = 'g1',
  String gameCode = 'wh3',
  String targetLanguageId = 'lang_fr',
}) {
  return Glossary(
    id: id,
    name: 'G',
    gameCode: gameCode,
    targetLanguageId: targetLanguageId,
    createdAt: 0,
    updatedAt: 0,
  );
}

GlossaryEntry _entry({
  required String id,
  required String sourceTerm,
  required String targetTerm,
  String glossaryId = 'g1',
  bool caseSensitive = false,
  String? notes,
}) {
  return GlossaryEntry(
    id: id,
    glossaryId: glossaryId,
    targetLanguageCode: 'fr',
    sourceTerm: sourceTerm,
    targetTerm: targetTerm,
    caseSensitive: caseSensitive,
    notes: notes,
    createdAt: 0,
    updatedAt: 0,
  );
}

void main() {
  late MockGlossaryRepository repo;
  late GlossaryFilterService service;

  setUp(() {
    repo = MockGlossaryRepository();
    service = GlossaryFilterService(repo);
  });

  void stubGlossaries(List<Glossary> glossaries) {
    when(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')))
        .thenAnswer((_) async => glossaries);
  }

  void stubEntries(String glossaryId, List<GlossaryEntry> entries) {
    when(() => repo.getEntriesByGlossary(
          glossaryId: glossaryId,
          targetLanguageCode: any(named: 'targetLanguageCode'),
        )).thenAnswer((_) async => entries);
  }

  Future<List<GlossaryTermWithVariants>> filter(List<String> sources,
      {String lang = 'lang_fr'}) {
    return service.filterRelevantTerms(
      sourceTexts: sources,
      gameCode: 'wh3',
      targetLanguageId: lang,
      targetLanguageCode: 'fr',
    );
  }

  group('filterRelevantTerms', () {
    test('returns empty for empty source texts without hitting the repo',
        () async {
      expect(await filter(const []), isEmpty);
      verifyNever(() => repo.getAllGlossaries(gameCode: any(named: 'gameCode')));
    });

    test('returns empty when no glossary matches the target language',
        () async {
      stubGlossaries([_glossary(targetLanguageId: 'lang_de')]);
      expect(await filter(['Empire troops']), isEmpty);
    });

    test('returns empty when applicable glossaries have no entries', () async {
      stubGlossaries([_glossary()]);
      stubEntries('g1', const []);
      expect(await filter(['Empire troops']), isEmpty);
    });

    test('keeps only terms that appear (whole word) in the source texts',
        () async {
      stubGlossaries([_glossary()]);
      stubEntries('g1', [
        _entry(id: 'e1', sourceTerm: 'Empire', targetTerm: 'Empire'),
        _entry(id: 'e2', sourceTerm: 'Dwarfs', targetTerm: 'Nains'),
      ]);

      final result = await filter(['The Empire marches']);

      expect(result, hasLength(1));
      expect(result.single.sourceTerm, 'Empire');
    });

    test('keeps a single matched entry per source-text occurrence', () async {
      // Two entries for the same term match at the same position; overlap
      // removal in GlossaryMatcher keeps only one, so only one variant emerges.
      stubGlossaries([_glossary(), _glossary(id: 'g2')]);
      stubEntries('g1', [
        _entry(id: 'e1', sourceTerm: 'Empire', targetTerm: 'Empire'),
      ]);
      stubEntries('g2', [
        _entry(
          id: 'e2',
          sourceTerm: 'Empire',
          targetTerm: 'Imperium',
          glossaryId: 'g2',
        ),
      ]);

      final result = await filter(['Empire']);

      expect(result, hasLength(1));
      expect(result.single.variants, hasLength(1));
    });
  });

  group('loadAllTerms', () {
    test('returns all grouped terms without source-text filtering', () async {
      stubGlossaries([_glossary()]);
      stubEntries('g1', [
        _entry(id: 'e1', sourceTerm: 'Empire', targetTerm: 'Empire'),
        _entry(id: 'e2', sourceTerm: 'Dwarfs', targetTerm: 'Nains'),
      ]);

      final result = await service.loadAllTerms(
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
        targetLanguageCode: 'fr',
      );

      expect(result.map((t) => t.sourceTerm), containsAll(['Empire', 'Dwarfs']));
    });

    test('groups same-term entries into variants and marks the group '
        'case-sensitive if any entry is', () async {
      stubGlossaries([_glossary(), _glossary(id: 'g2')]);
      stubEntries('g1', [
        _entry(id: 'e1', sourceTerm: 'Empire', targetTerm: 'Empire'),
      ]);
      stubEntries('g2', [
        _entry(
          id: 'e2',
          sourceTerm: 'empire',
          targetTerm: 'Imperium',
          glossaryId: 'g2',
          caseSensitive: true,
        ),
      ]);

      final result = await service.loadAllTerms(
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
        targetLanguageCode: 'fr',
      );

      expect(result, hasLength(1));
      final term = result.single;
      // Original case from the first grouped entry is preserved.
      expect(term.sourceTerm, 'Empire');
      expect(term.variants, hasLength(2));
      // caseSensitive is true if ANY grouped entry is case sensitive.
      expect(term.caseSensitive, isTrue);
    });

    test('returns empty when no applicable glossary', () async {
      stubGlossaries([_glossary(targetLanguageId: 'lang_de')]);
      final result = await service.loadAllTerms(
        gameCode: 'wh3',
        targetLanguageId: 'lang_fr',
        targetLanguageCode: 'fr',
      );
      expect(result, isEmpty);
    });
  });

  group('estimateTokenCount', () {
    test('returns 0 for no terms', () {
      expect(service.estimateTokenCount(const []), 0);
    });

    test('adds header overhead plus per-term tokens', () async {
      stubGlossaries([_glossary()]);
      stubEntries('g1', [
        _entry(id: 'e1', sourceTerm: 'Empire', targetTerm: 'Empire'),
      ]);
      final terms = await filter(['Empire']);

      final estimate = service.estimateTokenCount(terms);
      // 10 base header + the term's own estimate (> 0).
      expect(estimate, greaterThan(10));
    });
  });
}
