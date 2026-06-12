import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/llm_batch_adjuster.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';

import '../../../helpers/fakes/fake_token_calculator.dart';

class _MockFactory extends Mock implements LlmProviderFactory {}

class _MockProvider extends Mock implements ILlmProvider {}

LlmRequest _request(Map<String, String> texts, {String system = 'system prompt'}) =>
    LlmRequest(
      requestId: 'r1',
      targetLanguage: 'fr',
      texts: texts,
      systemPrompt: system,
      timestamp: DateTime(2026, 1, 1),
    );

void main() {
  setUpAll(() => registerFallbackValue(_request(const {'k': 'v'})));

  late _MockFactory factory;
  late _MockProvider provider;
  late LlmBatchAdjuster adjuster;

  setUp(() {
    factory = _MockFactory();
    provider = _MockProvider();
    adjuster = LlmBatchAdjuster(
      providerFactory: factory,
      tokenCalculator: FakeTokenCalculator(),
    );
    when(() => factory.getProvider(any())).thenReturn(provider);
    when(() => provider.config).thenReturn(LlmProviderConfig.anthropic);
  });

  group('pure token math', () {
    test('calculateTextEntryTokens sums key + value + output estimate', () {
      final tokens = adjuster.calculateTextEntryTokens('a_key', 'some value');
      expect(tokens, greaterThan(0));
    });

    test('calculateOverheadTokens grows with added context', () {
      final base = adjuster.calculateOverheadTokens(_request({'k': 'v'}));
      final withContext = adjuster.calculateOverheadTokens(
        _request({'k': 'v'}).copyWith(
          gameContext: 'a long game context string here',
          projectContext: 'a project context describing the mod',
        ),
      );
      expect(withContext, greaterThan(base));
    });

    test('estimateTotalTokens = overhead + per-entry text tokens', () {
      final req = _request({'a': 'alpha', 'b': 'beta'});
      final total = adjuster.estimateTotalTokens(req);
      final overhead = adjuster.calculateOverheadTokens(req);
      expect(total, greaterThan(overhead));
    });
  });

  group('splitRequestByTokens', () {
    test('keeps everything in one batch when it fits', () {
      final req = _request({'a': 'x', 'b': 'y'});
      final batches = adjuster.splitRequestByTokens(req, 100000);
      expect(batches, hasLength(1));
      expect(batches.first.texts.length, 2);
    });

    test('splits into multiple batches under a tight token budget', () {
      final req = _request({
        'a': 'aaaaaaaa',
        'b': 'bbbbbbbb',
        'c': 'cccccccc',
      });
      // Each entry costs a few tokens; a tiny budget forces one entry per batch.
      final batches = adjuster.splitRequestByTokens(req, 6);
      expect(batches.length, greaterThan(1));
      // Batch ids carry the batch index suffix.
      expect(batches.first.requestId, contains('_batch_0'));
    });

    test('skips an entry that cannot fit in any batch', () {
      final req = _request({'huge': 'x' * 1000, 'ok': 'y'});
      final batches = adjuster.splitRequestByTokens(req, 5);
      final keptKeys = batches.expand((b) => b.texts.keys).toSet();
      expect(keptKeys, isNot(contains('huge')));
    });
  });

  group('validateBatchSize / adjustBatchSize', () {
    test('valid when the provider estimate is within the limit', () async {
      when(() => provider.estimateRequestTokens(any())).thenReturn(100);
      final r = await adjuster.validateBatchSize(_request({'k': 'v'}), 'anthropic');
      expect(r.unwrap(), isTrue);
    });

    test('invalid when the estimate exceeds the provider limit', () async {
      when(() => provider.estimateRequestTokens(any()))
          .thenReturn(999999999);
      final r = await adjuster.validateBatchSize(_request({'k': 'v'}), 'anthropic');
      expect(r.unwrap(), isFalse);
    });

    test('adjustBatchSize returns the request as-is when it is valid', () async {
      when(() => provider.estimateRequestTokens(any())).thenReturn(100);
      final r = await adjuster.adjustBatchSize(_request({'k': 'v'}), 'anthropic');
      expect(r.unwrap(), hasLength(1));
    });

    test('adjustBatchSize splits an oversized request', () async {
      when(() => provider.estimateRequestTokens(any()))
          .thenReturn(999999999); // forces a split
      final req = _request({'a': 'alpha', 'b': 'beta', 'c': 'gamma'});
      final r = await adjuster.adjustBatchSize(req, 'anthropic');
      expect(r.isOk, isTrue);
      expect(r.unwrap(), isNotEmpty);
    });
  });
}
