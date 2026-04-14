import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// Reusable `TokenCalculator` fake.
///
/// The real `TokenCalculator` eagerly loads the tiktoken cl100k_base
/// encoding in its constructor, which crashes with a type error unless
/// another test in the run has already warmed it up. Provider tests never
/// exercise `translate()`, so deterministic stand-ins are sufficient.
///
/// Defaults: token counts = `text.length ~/ 4` (a reasonable approximation
/// of English/Latin tokenization ratios). Override specific methods in
/// subclasses when a test needs exact values.
class FakeTokenCalculator extends Fake implements TokenCalculator {
  @override
  int calculateTokens(String text) => text.length ~/ 4;

  @override
  int estimateRequestTokens(LlmRequest request) {
    final textChars =
        request.texts.values.fold<int>(0, (sum, v) => sum + v.length);
    return (request.systemPrompt.length + textChars) ~/ 4;
  }

  @override
  int calculateAnthropicTokens(String text) => text.length ~/ 4;

  @override
  int estimateAnthropicRequestTokens(LlmRequest request) {
    final textChars =
        request.texts.values.fold<int>(0, (sum, v) => sum + v.length);
    return (request.systemPrompt.length + textChars) ~/ 4;
  }

  @override
  int calculateCharacterCount(Map<String, String> texts) {
    return texts.values.fold<int>(0, (sum, v) => sum + v.length);
  }
}
