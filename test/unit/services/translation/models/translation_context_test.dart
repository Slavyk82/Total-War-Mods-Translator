import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/translation/models/translation_context.dart';

TranslationContext _ctx({String? providerId}) => TranslationContext(
      id: 'c1',
      projectId: 'p1',
      projectLanguageId: 'pl1',
      providerId: providerId,
      targetLanguage: 'fr',
      gameContext: 'lore',
      fewShotExamples: const [
        {'source': 'Hi', 'target': 'Salut'},
      ],
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 2),
    );

void main() {
  group('providerCode', () {
    test('is null when providerId is null', () {
      expect(_ctx().providerCode, isNull);
    });

    test('strips the provider_ prefix', () {
      expect(_ctx(providerId: 'provider_anthropic').providerCode, 'anthropic');
    });

    test('returns the value unchanged when it has no prefix', () {
      expect(_ctx(providerId: 'openai').providerCode, 'openai');
    });
  });

  group('defaults', () {
    test('sensible defaults are applied', () {
      final c = _ctx();
      expect(c.preserveFormatting, isTrue);
      expect(c.unitsPerBatch, 100);
      expect(c.parallelBatches, 1);
      expect(c.skipTranslationMemory, isFalse);
    });
  });

  group('copyWith / equality / json', () {
    test('copyWith overrides only the targeted field', () {
      final c = _ctx();
      expect(c.copyWith(targetLanguage: 'de').targetLanguage, 'de');
      expect(c.copyWith(targetLanguage: 'de').id, 'c1');
    });

    test('equality keys on identity + context fields', () {
      expect(_ctx(), equals(_ctx()));
      expect(_ctx().hashCode, _ctx().hashCode);
    });

    test('json round-trip preserves scalar fields and few-shot examples', () {
      final restored = TranslationContext.fromJson(_ctx().toJson());
      expect(restored.id, 'c1');
      expect(restored.targetLanguage, 'fr');
      expect(restored.gameContext, 'lore');
      expect(restored.fewShotExamples, hasLength(1));
    });
  });
}
