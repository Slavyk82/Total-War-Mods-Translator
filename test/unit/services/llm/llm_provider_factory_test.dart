import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/providers/anthropic_provider.dart';
import 'package:twmt/services/llm/providers/deepl_provider.dart';
import 'package:twmt/services/llm/providers/deepseek_provider.dart';
import 'package:twmt/services/llm/providers/gemini_provider.dart';
import 'package:twmt/services/llm/providers/openai_provider.dart';

void main() {
  group('LlmProviderFactory', () {
    late LlmProviderFactory factory;

    setUp(() {
      // Factory is a singleton; reset to defaults to ensure a clean state
      // because prior tests may have registered/removed providers.
      factory = LlmProviderFactory();
      factory.resetToDefaults();
    });

    test("returns OpenAiProvider for 'openai'", () {
      expect(factory.getProvider('openai'), isA<OpenAiProvider>());
    });

    test("returns AnthropicProvider for 'anthropic'", () {
      expect(factory.getProvider('anthropic'), isA<AnthropicProvider>());
    });

    test("returns GeminiProvider for 'gemini'", () {
      expect(factory.getProvider('gemini'), isA<GeminiProvider>());
    });

    test("returns DeepSeekProvider for 'deepseek'", () {
      expect(factory.getProvider('deepseek'), isA<DeepSeekProvider>());
    });

    test("returns DeepLProvider for 'deepl'", () {
      expect(factory.getProvider('deepl'), isA<DeepLProvider>());
    });

    test("throws LlmConfigurationException for unknown provider code", () {
      expect(
        () => factory.getProvider('xyz'),
        throwsA(
          isA<LlmConfigurationException>()
              .having((e) => e.code, 'code', 'UNKNOWN_PROVIDER'),
        ),
      );
    });
  });
}
