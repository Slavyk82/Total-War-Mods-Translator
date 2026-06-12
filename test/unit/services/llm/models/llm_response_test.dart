import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/models/llm_response.dart';

LlmResponse _response() => LlmResponse(
      requestId: 'r1',
      translations: const {'k': 'v'},
      providerCode: 'anthropic',
      modelName: 'claude',
      inputTokens: 10,
      outputTokens: 20,
      totalTokens: 30,
      processingTimeMs: 100,
      timestamp: DateTime(2026, 1, 1),
      finishReason: 'stop',
    );

void main() {
  group('LlmResponse', () {
    test('copyWith overrides only the targeted field', () {
      final r = _response();
      expect(r.copyWith(totalTokens: 99).totalTokens, 99);
      expect(r.copyWith(totalTokens: 99).requestId, 'r1');
    });

    test('equality + hashCode are field-based', () {
      expect(_response(), equals(_response()));
      expect(_response().hashCode, _response().hashCode);
    });

    test('json round-trip', () {
      final restored = LlmResponse.fromJson(_response().toJson());
      expect(restored.requestId, 'r1');
      expect(restored.translations, {'k': 'v'});
      expect(restored.finishReason, 'stop');
    });
  });

  group('BatchTranslationResult', () {
    BatchTranslationResult batch({int total = 4, int ok = 3}) =>
        BatchTranslationResult(
          batchId: 'b1',
          totalUnits: total,
          successfulUnits: ok,
          failedUnits: total - ok,
          responses: [_response()],
          errors: const {'x': 'boom'},
          totalTokens: 30,
          totalProcessingTimeMs: 100,
          startTime: DateTime(2026, 1, 1, 0, 0, 0),
          endTime: DateTime(2026, 1, 1, 0, 0, 5),
        );

    test('successRate is successfulUnits / totalUnits', () {
      expect(batch(total: 4, ok: 3).successRate, 0.75);
      expect(batch(total: 0, ok: 0).successRate, 0.0);
    });

    test('duration is endTime - startTime', () {
      expect(batch().duration, const Duration(seconds: 5));
    });

    test('json round-trip preserves scalar fields and errors', () {
      // Nested LlmResponse objects are not converted to maps by the generated
      // toJson (no explicitToJson), so round-trip with an empty responses list.
      final empty = BatchTranslationResult(
        batchId: 'b1',
        totalUnits: 4,
        successfulUnits: 3,
        failedUnits: 1,
        responses: const [],
        errors: const {'x': 'boom'},
        totalTokens: 30,
        totalProcessingTimeMs: 100,
        startTime: DateTime(2026, 1, 1, 0, 0, 0),
        endTime: DateTime(2026, 1, 1, 0, 0, 5),
      );
      final restored = BatchTranslationResult.fromJson(empty.toJson());
      expect(restored.batchId, 'b1');
      expect(restored.errors, {'x': 'boom'});
      expect(restored.successfulUnits, 3);
    });
  });
}
