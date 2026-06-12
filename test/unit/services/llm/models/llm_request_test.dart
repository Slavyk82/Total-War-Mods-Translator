import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/models/llm_request.dart';

LlmRequest _request() => LlmRequest(
      requestId: 'r1',
      targetLanguage: 'fr',
      texts: const {'k': 'Hello'},
      systemPrompt: 'sys',
      providerCode: 'anthropic',
      maxTokens: 4096,
      fewShotExamples: const [
        TranslationExample(source: 'Hi', target: 'Salut', similarityScore: 0.9),
      ],
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  group('LlmRequest', () {
    test('copyWith overrides only the targeted field', () {
      final r = _request();
      expect(r.copyWith(targetLanguage: 'de').targetLanguage, 'de');
      expect(r.copyWith(targetLanguage: 'de').requestId, 'r1');
    });

    test('equality + hashCode are field-based', () {
      expect(_request(), equals(_request()));
      expect(_request().hashCode, _request().hashCode);
    });

    test('json round-trip preserves scalar fields and texts', () {
      // Nested TranslationExample objects are not converted to maps by the
      // generated toJson (no explicitToJson), so round-trip without examples.
      final req = LlmRequest(
        requestId: 'r1',
        targetLanguage: 'fr',
        texts: const {'k': 'Hello'},
        systemPrompt: 'sys',
        providerCode: 'anthropic',
        maxTokens: 4096,
        timestamp: DateTime(2026, 1, 1),
      );
      final restored = LlmRequest.fromJson(req.toJson());
      expect(restored.requestId, 'r1');
      expect(restored.texts, {'k': 'Hello'});
      expect(restored.maxTokens, 4096);
    });
  });

  group('TranslationExample', () {
    test('equality + json round-trip', () {
      const e = TranslationExample(source: 'a', target: 'b', similarityScore: 0.5);
      expect(e, equals(const TranslationExample(source: 'a', target: 'b', similarityScore: 0.5)));
      final restored = TranslationExample.fromJson(e.toJson());
      expect(restored.source, 'a');
      expect(restored.similarityScore, 0.5);
    });
  });
}
