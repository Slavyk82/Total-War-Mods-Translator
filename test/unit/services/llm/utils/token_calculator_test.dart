import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/models/llm_request.dart';
import 'package:twmt/services/llm/utils/token_calculator.dart';

// Tests for TokenCalculator. TokenCalculator loads the tiktoken cl100k_base
// encoding eagerly in its constructor. On a cold Flutter test VM this can
// crash with `type 'List<dynamic>' is not a subtype of type 'String'`.
//
// Strategy: initialise TestWidgetsFlutterBinding in setUpAll and then pre-warm
// the singleton once. TokenCalculator is a singleton, so any subsequent
// construction returns the cached instance. If the first construction blows
// up, the crash is isolated to setUpAll and the file fails fast and loud
// rather than reporting misleading per-test errors.

void main() {
  late TokenCalculator calc;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Pre-warm the singleton. If tiktoken fails to load, this crashes once
    // here rather than inside each individual test case.
    calc = TokenCalculator();
    calc.clearCache();
  });

  LlmRequest buildRequest({
    Map<String, String>? texts,
    String? systemPrompt,
    String targetLanguage = 'fr',
  }) {
    return LlmRequest(
      requestId: 'req-tc-1',
      targetLanguage: targetLanguage,
      texts: texts ?? const {'key1': 'hello world'},
      systemPrompt: systemPrompt ?? 'Translate these strings.',
      timestamp: DateTime(2026, 4, 14, 12, 0, 0),
    );
  }

  group('TokenCalculator.calculateTokens', () {
    test('returns a small positive token count for a short ASCII string', () {
      final tokens = calc.calculateTokens('hello world');
      // cl100k_base typically encodes "hello world" as ~2 tokens. Use a
      // generous envelope so the test survives minor encoder updates.
      expect(tokens, greaterThan(0));
      expect(tokens, lessThan(10));
    });

    test('returns 0 for an empty string (short-circuit before encoder)', () {
      expect(calc.calculateTokens(''), 0);
    });

    test('handles unicode and emoji without throwing', () {
      expect(() => calc.calculateTokens('👋 hello ß привет'), returnsNormally);
      final tokens = calc.calculateTokens('👋 hello ß привет');
      expect(tokens, greaterThan(0));
    });

    test('handles a 10k-character string and returns a large token count', () {
      final big = 'lorem ipsum dolor sit amet ' * 400; // ~10,800 chars
      final tokens = calc.calculateTokens(big);
      // Very rough sanity bounds: tiktoken averages ~4 chars/token on English
      // prose, so 10k chars should land well above 500 tokens.
      expect(tokens, greaterThan(500));
      expect(tokens, lessThan(big.length));
    });

    test('cached call returns the same value as the initial computation', () {
      const sample = 'repeatable text fragment';
      final first = calc.calculateTokens(sample);
      final second = calc.calculateTokens(sample);
      expect(second, first);
    });
  });

  group('TokenCalculator.estimateRequestTokens', () {
    test('sums system prompt + input texts within sane character bounds', () {
      final request = buildRequest(
        systemPrompt: 'You are a translator.',
        texts: const {
          'k1': 'Hello, brave adventurer.',
          'k2': 'Welcome to Hexus.',
        },
      );
      final totalChars = request.systemPrompt.length +
          request.texts.entries.fold<int>(
            0,
            (sum, e) => sum + e.key.length + e.value.length,
          );

      final estimate = calc.estimateRequestTokens(request);

      // Sane lower bound: token count cannot be less than chars/8 even after
      // shrinking multi-byte glyphs. Sane upper bound: estimate includes
      // output projection (~30% of input * language multiplier * 1.2 + 10
      // per text), so total tokens should stay well under total chars for
      // typical English prose.
      expect(estimate, greaterThan(totalChars ~/ 8));
      expect(estimate, lessThan(totalChars * 2));
    });
  });

  group('TokenCalculator.calculateAnthropicTokens', () {
    test('applies a 7.5% correction factor on top of base token count', () {
      const sample = 'anthropic correction sample text';
      final base = calc.calculateTokens(sample);
      final anthropic = calc.calculateAnthropicTokens(sample);
      // Anthropic count should be >= base and <= base * 1.075 rounded up.
      expect(anthropic, greaterThanOrEqualTo(base));
      expect(anthropic, lessThanOrEqualTo((base * 1.075).ceil()));
    });
  });

  group('TokenCalculator.calculateCharacterCount', () {
    test('sums values only (DeepL billing mode)', () {
      final count = calc.calculateCharacterCount(const {
        'k1': 'abcd', // 4
        'k2': 'hello', // 5
      });
      // Only values count; keys are ignored.
      expect(count, 9);
    });
  });
}
