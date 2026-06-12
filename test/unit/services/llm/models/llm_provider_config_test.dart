import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/models/llm_provider_config.dart';

void main() {
  group('LlmProviderConfig presets', () {
    test('anthropic / openai / deepl / deepseek / gemini expose their codes', () {
      expect(LlmProviderConfig.anthropic.providerCode, 'anthropic');
      expect(LlmProviderConfig.anthropic.supportsStreaming, isTrue);
      expect(LlmProviderConfig.openai.providerCode, 'openai');
      expect(LlmProviderConfig.deepl.providerCode, 'deepl');
      expect(LlmProviderConfig.deepl.supportsStreaming, isFalse);
      expect(LlmProviderConfig.deepl.defaultRateLimitTpm, isNull);
      expect(LlmProviderConfig.deepseek.providerCode, 'deepseek');
      expect(LlmProviderConfig.gemini.providerCode, 'gemini');
    });

    test('copyWith overrides a field; equality is value-based', () {
      final base = LlmProviderConfig.anthropic;
      expect(base.copyWith(defaultRateLimitRpm: 10).defaultRateLimitRpm, 10);
      expect(base.copyWith(defaultRateLimitRpm: 10).providerCode, 'anthropic');
      expect(base, equals(LlmProviderConfig.anthropic));
      expect(base.hashCode, LlmProviderConfig.anthropic.hashCode);
    });

    test('toJson emits the expected top-level fields', () {
      final json = LlmProviderConfig.anthropic.toJson();
      expect(json['providerCode'] ?? json['provider_code'], 'anthropic');
      expect(json.containsKey('retryConfig') || json.containsKey('retry_config'),
          isTrue);
    });
  });

  group('RetryConfig.calculateDelay', () {
    const cfg = RetryConfig.defaultConfig; // initial 1000ms, x2, max 30000

    test('returns 0 for a non-positive attempt', () {
      expect(cfg.calculateDelay(0), 0);
      expect(cfg.calculateDelay(-1), 0);
    });

    test('grows exponentially with the attempt number', () {
      expect(cfg.calculateDelay(1), 1000); // 1000 * 2^0
      expect(cfg.calculateDelay(2), 2000); // 1000 * 2^1
      expect(cfg.calculateDelay(3), 4000); // 1000 * 2^2
    });

    test('is capped at maxDelayMs', () {
      expect(cfg.calculateDelay(20), 30000);
    });

    test('json round-trip preserves the config', () {
      final restored = RetryConfig.fromJson(cfg.toJson());
      expect(restored, equals(cfg));
      expect(restored.backoffMultiplier, 2.0);
    });
  });

  group('Math.pow helper', () {
    test('computes integer powers', () {
      expect(Math.pow(2.0, 0), 1.0);
      expect(Math.pow(2.0, 3), 8.0);
      expect(Math.pow(3.0, 2), 9.0);
    });
  });
}
