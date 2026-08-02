import 'package:mocktail/mocktail.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

/// Reusable `TokenCalculator` fake.
///
/// The real `TokenCalculator` parses the full cl100k_base ranks table
/// (100,256 entries) in its constructor. Provider tests never exercise
/// `translate()`, so deterministic stand-ins are both sufficient and much
/// cheaper than building the encoding in every suite.
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
