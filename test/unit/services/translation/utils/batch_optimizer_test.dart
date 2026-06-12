import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/translation/models/translation_exceptions.dart';
import 'package:twmt/services/translation/utils/batch_optimizer.dart';

import '../../../../helpers/fakes/fake_token_calculator.dart';

TranslationUnit _unit(String key, String source) => TranslationUnit(
      id: 'id-$key',
      projectId: 'p',
      key: key,
      sourceText: source,
      createdAt: 0,
      updatedAt: 0,
    );

final _provider = LlmProviderConfig.anthropic; // maxTokensPerRequest 200000

void main() {
  final optimizer = BatchOptimizer(FakeTokenCalculator());

  group('calculateOptimalBatchSize', () {
    test('throws on an empty units list', () async {
      expect(
        () => optimizer.calculateOptimalBatchSize(
          units: [],
          providerConfig: _provider,
          systemPromptTokens: 100,
          contextTokens: 0,
          targetLanguage: 'fr',
        ),
        throwsA(isA<EmptyBatchException>()),
      );
    });

    test('throws when fixed prompts exceed the token budget', () async {
      expect(
        () => optimizer.calculateOptimalBatchSize(
          units: [_unit('k', 'Hello world')],
          providerConfig: _provider,
          systemPromptTokens: 1000000, // > 200000 budget
          contextTokens: 0,
          targetLanguage: 'fr',
        ),
        throwsA(isA<BatchOptimizationException>()),
      );
    });

    test('returns a size clamped to [1, 100]', () async {
      final size = await optimizer.calculateOptimalBatchSize(
        units: List.generate(50, (i) => _unit('k$i', 'Some source text $i')),
        providerConfig: _provider,
        systemPromptTokens: 500,
        contextTokens: 200,
        targetLanguage: 'fr',
      );
      expect(size, inInclusiveRange(1, 100));
    });
  });

  group('splitIntoBatches', () {
    test('returns an empty list for no units', () {
      expect(optimizer.splitIntoBatches(units: [], optimalBatchSize: 5), isEmpty);
    });

    test('throws for a non-positive batch size', () {
      expect(
        () => optimizer.splitIntoBatches(
            units: [_unit('k', 's')], optimalBatchSize: 0),
        throwsA(isA<BatchOptimizationException>()),
      );
    });

    test('chunks units into batches of the given size', () {
      final units = List.generate(7, (i) => _unit('k$i', 's'));
      final batches = optimizer.splitIntoBatches(units: units, optimalBatchSize: 3);
      expect(batches.map((b) => b.length), [3, 3, 1]);
    });
  });

  group('estimateBatchTokens / validateBatchSize', () {
    test('an empty batch costs only the fixed prompts', () async {
      final tokens = await optimizer.estimateBatchTokens(
        units: [],
        providerCode: 'anthropic',
        systemPromptTokens: 100,
        contextTokens: 50,
        targetLanguage: 'fr',
      );
      expect(tokens, 150);
    });

    test('a small batch fits, an enormous fixed prompt does not', () async {
      expect(
        await optimizer.validateBatchSize(
          units: [_unit('k', 'Hello')],
          providerConfig: _provider,
          systemPromptTokens: 100,
          contextTokens: 0,
          targetLanguage: 'fr',
        ),
        isTrue,
      );
      expect(
        await optimizer.validateBatchSize(
          units: [_unit('k', 'Hello')],
          providerConfig: _provider,
          systemPromptTokens: 999999,
          contextTokens: 0,
          targetLanguage: 'fr',
        ),
        isFalse,
      );
    });
  });

  group('adjustBasedOnHistory', () {
    test('returns the current size when either token count is zero', () {
      expect(
        optimizer.adjustBasedOnHistory(
            currentBatchSize: 20, estimatedTokens: 0, actualTokens: 100),
        20,
      );
    });

    test('shrinks the batch when actual exceeds estimated', () {
      // actual 2x estimated -> adjustmentFactor 0.5 -> 20 -> 10
      expect(
        optimizer.adjustBasedOnHistory(
            currentBatchSize: 20, estimatedTokens: 1000, actualTokens: 2000),
        10,
      );
    });

    test('grows the batch (clamped) when actual is below estimated', () {
      // actual 0.5x estimated -> factor 2 -> 60 -> clamped to 100 max anyway
      expect(
        optimizer.adjustBasedOnHistory(
            currentBatchSize: 60, estimatedTokens: 1000, actualTokens: 500),
        100,
      );
    });
  });
}
