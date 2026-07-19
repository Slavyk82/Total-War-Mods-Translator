import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/providers/translation_runner_providers.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';

class MockTranslationOrchestrator extends Mock
    implements ITranslationOrchestrator {}

void main() {
  group('headlessBatchTranslationRunnerProvider', () {
    test('builds a HeadlessBatchTranslationRunner from injected dependencies',
        () {
      final container = ProviderContainer(overrides: [
        translationOrchestratorProvider
            .overrideWithValue(MockTranslationOrchestrator()),
      ]);
      addTearDown(container.dispose);

      final runner = container.read(headlessBatchTranslationRunnerProvider);

      expect(runner, isA<HeadlessBatchTranslationRunner>());
      // No batch has been started through the freshly built runner.
      expect(runner.currentBatchId, isNull);
    });

    test('caches a single runner instance per container', () {
      final container = ProviderContainer(overrides: [
        translationOrchestratorProvider
            .overrideWithValue(MockTranslationOrchestrator()),
      ]);
      addTearDown(container.dispose);

      final first = container.read(headlessBatchTranslationRunnerProvider);
      final second = container.read(headlessBatchTranslationRunnerProvider);

      expect(identical(first, second), isTrue);
    });
  });
}
