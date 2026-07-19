import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/events/tm_events.dart';

void main() {
  group('TranslationAddedToTmEvent', () {
    TranslationAddedToTmEvent makeEvent() => TranslationAddedToTmEvent(
          versionId: 'v1',
          unitId: 'u1',
          tmId: 'tm1',
          sourceText: 'Hello',
          translatedText: 'Bonjour',
          targetLanguageId: 'lang_fr',
          gameContext: 'wh3',
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.tmId, 'tm1');
      expect(event.sourceText, 'Hello');
      expect(event.translatedText, 'Bonjour');
      expect(event.targetLanguageId, 'lang_fr');
      expect(event.gameContext, 'wh3');

      // Inherited from DomainEvent.now()
      expect(event.eventId, isNotEmpty);
      expect(event.timestamp, isA<DateTime>());
      expect(event.eventType, 'TranslationAddedToTmEvent');
      expect(event.occurredAt, event.timestamp);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes key fields', () {
      expect(
        makeEvent().toString(),
        'TranslationAddedToTmEvent(versionId: v1, tmId: tm1, context: wh3)',
      );
    });
  });

  group('TmEntryAddedEvent', () {
    TmEntryAddedEvent makeEvent() => TmEntryAddedEvent(
          tmId: 'tm1',
          sourceHash: 'hash',
          targetLanguageId: 'lang_fr',
          gameContext: 'wh3',
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.tmId, 'tm1');
      expect(event.sourceHash, 'hash');
      expect(event.targetLanguageId, 'lang_fr');
      expect(event.gameContext, 'wh3');
      expect(event.eventId, isNotEmpty);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes key fields', () {
      expect(
        makeEvent().toString(),
        'TmEntryAddedEvent(tmId: tm1, context: wh3)',
      );
    });
  });

  group('TmMatchFoundEvent', () {
    TmMatchFoundEvent makeEvent({double matchConfidence = 0.95}) =>
        TmMatchFoundEvent(
          tmId: 'tm1',
          versionId: 'v1',
          unitId: 'u1',
          matchConfidence: matchConfidence,
          sourceText: 'Hello',
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.tmId, 'tm1');
      expect(event.versionId, 'v1');
      expect(event.unitId, 'u1');
      expect(event.matchConfidence, 0.95);
      expect(event.sourceText, 'Hello');
    });

    test('isExactMatch at the 0.99 threshold', () {
      expect(makeEvent(matchConfidence: 1.0).isExactMatch, isTrue);
      expect(makeEvent(matchConfidence: 0.99).isExactMatch, isTrue);
      expect(makeEvent(matchConfidence: 0.985).isExactMatch, isFalse);
    });

    test('isFuzzyMatch and matchType mirror isExactMatch', () {
      final exact = makeEvent(matchConfidence: 1.0);
      expect(exact.isFuzzyMatch, isFalse);
      expect(exact.matchType, 'exact');

      final fuzzy = makeEvent(matchConfidence: 0.9);
      expect(fuzzy.isFuzzyMatch, isTrue);
      expect(fuzzy.matchType, 'fuzzy');
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes match type and percentage', () {
      expect(
        makeEvent(matchConfidence: 0.5).toString(),
        'TmMatchFoundEvent(tmId: tm1, versionId: v1, match: fuzzy (50.0%))',
      );
    });
  });

  group('TmEntryUpdatedEvent', () {
    TmEntryUpdatedEvent makeEvent() => TmEntryUpdatedEvent(
          tmId: 'tm1',
          newUsageCount: 4,
          updateReason: 'usage',
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.tmId, 'tm1');
      expect(event.newUsageCount, 4);
      expect(event.updateReason, 'usage');
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes key fields', () {
      expect(
        makeEvent().toString(),
        'TmEntryUpdatedEvent(tmId: tm1, usage: 4, reason: usage)',
      );
    });
  });

  group('TmSuggestion', () {
    TmSuggestion makeSuggestion({
      double matchConfidence = 0.95,
      int usageCount = 3,
    }) =>
        TmSuggestion(
          tmId: 'tm1',
          translatedText: 'Bonjour',
          matchConfidence: matchConfidence,
          usageCount: usageCount,
        );

    test('constructs and exposes fields', () {
      final suggestion = makeSuggestion();
      expect(suggestion.tmId, 'tm1');
      expect(suggestion.translatedText, 'Bonjour');
      expect(suggestion.matchConfidence, 0.95);
      expect(suggestion.usageCount, 3);
    });

    test('isExactMatch at the 0.99 threshold', () {
      expect(makeSuggestion(matchConfidence: 0.99).isExactMatch, isTrue);
      expect(makeSuggestion(matchConfidence: 0.985).isExactMatch, isFalse);
    });

    test('isFrequentlyUsed at the 5 uses threshold', () {
      expect(makeSuggestion(usageCount: 5).isFrequentlyUsed, isTrue);
      expect(makeSuggestion(usageCount: 4).isFrequentlyUsed, isFalse);
    });

    test('toJson is not implemented', () {
      expect(() => makeSuggestion().toJson(), throwsUnimplementedError);
    });

    test('toString includes match percentage and usage', () {
      expect(
        makeSuggestion(matchConfidence: 0.5, usageCount: 3).toString(),
        'TmSuggestion(match: 50.0%, usage: 3)',
      );
    });
  });

  group('TmSuggestionsProvidedEvent', () {
    final exact = TmSuggestion(
      tmId: 'tm1',
      translatedText: 'Bonjour',
      matchConfidence: 1.0,
      usageCount: 1,
    );
    final fuzzy = TmSuggestion(
      tmId: 'tm2',
      translatedText: 'Salut',
      matchConfidence: 0.9,
      usageCount: 2,
    );

    TmSuggestionsProvidedEvent makeEvent(List<TmSuggestion> suggestions) =>
        TmSuggestionsProvidedEvent(
          unitId: 'u1',
          sourceText: 'Hello',
          suggestions: suggestions,
        );

    test('constructs and exposes fields', () {
      final event = makeEvent([exact, fuzzy]);
      expect(event.unitId, 'u1');
      expect(event.sourceText, 'Hello');
      expect(event.suggestions, [exact, fuzzy]);
    });

    test('suggestionCount', () {
      expect(makeEvent([]).suggestionCount, 0);
      expect(makeEvent([exact, fuzzy]).suggestionCount, 2);
    });

    test('hasExactMatch', () {
      expect(makeEvent([exact, fuzzy]).hasExactMatch, isTrue);
      expect(makeEvent([fuzzy]).hasExactMatch, isFalse);
      expect(makeEvent([]).hasExactMatch, isFalse);
    });

    test('bestMatch is first suggestion or null', () {
      expect(makeEvent([]).bestMatch, isNull);
      expect(makeEvent([fuzzy, exact]).bestMatch, fuzzy);
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent([]).toJson(), throwsUnimplementedError);
    });

    test('toString includes count and hasExact', () {
      expect(
        makeEvent([exact, fuzzy]).toString(),
        'TmSuggestionsProvidedEvent(unitId: u1, suggestions: 2, '
        'hasExact: true)',
      );
    });
  });

  group('TmCacheRebuiltEvent', () {
    TmCacheRebuiltEvent makeEvent() => TmCacheRebuiltEvent(
          totalEntries: 1000,
          gameContextsCount: 3,
          rebuildDuration: const Duration(milliseconds: 1500),
        );

    test('constructs and exposes fields', () {
      final event = makeEvent();
      expect(event.totalEntries, 1000);
      expect(event.gameContextsCount, 3);
      expect(event.rebuildDuration, const Duration(milliseconds: 1500));
    });

    test('toJson is not implemented', () {
      expect(() => makeEvent().toJson(), throwsUnimplementedError);
    });

    test('toString includes entries, contexts and duration', () {
      expect(
        makeEvent().toString(),
        'TmCacheRebuiltEvent(entries: 1000, contexts: 3, duration: 1500ms)',
      );
    });
  });
}
