import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/llm/llm_provider_factory.dart';
import 'package:twmt/services/llm/models/llm_exceptions.dart';
import 'package:twmt/services/llm/providers/i_llm_provider.dart';

import '../../helpers/test_bootstrap.dart';

class _FakeProvider extends Fake implements ILlmProvider {}

void main() {
  late LlmProviderFactory factory;

  setUp(() async {
    // Built-in providers fall back to ServiceLocator.get<ILoggingService>() in
    // their constructors, so a fake logger must be registered before the
    // singleton (re)builds them.
    await TestBootstrap.registerFakes();
    // The factory is a process-wide singleton; reset it before each test so
    // state from earlier tests (or the rest of the suite) can't leak in.
    factory = LlmProviderFactory();
    factory.resetToDefaults();
  });

  tearDown(() => LlmProviderFactory().resetToDefaults());

  test('is a singleton', () {
    expect(LlmProviderFactory(), same(LlmProviderFactory()));
  });

  test('pre-registers the five built-in providers', () {
    expect(
      factory.getAvailableProviders(),
      containsAll(['anthropic', 'openai', 'deepl', 'deepseek', 'gemini']),
    );
  });

  test('getProvider is case-insensitive', () {
    expect(factory.getProvider('ANTHROPIC'), isNotNull);
    expect(factory.getProvider('Anthropic'),
        same(factory.getProvider('anthropic')));
  });

  test('getProvider throws a configuration exception for unknown codes', () {
    expect(
      () => factory.getProvider('nope'),
      throwsA(isA<LlmConfigurationException>()),
    );
  });

  test('hasProvider reflects registration, case-insensitively', () {
    expect(factory.hasProvider('openai'), isTrue);
    expect(factory.hasProvider('OpenAI'), isTrue);
    expect(factory.hasProvider('missing'), isFalse);
  });

  test('getAllProviders returns an unmodifiable view', () {
    final all = factory.getAllProviders();
    expect(all.keys, contains('anthropic'));
    expect(() => all['x'] = _FakeProvider(), throwsUnsupportedError);
  });

  test('register and unregister a custom provider', () {
    final custom = _FakeProvider();
    factory.registerProvider('Custom', custom);
    expect(factory.hasProvider('custom'), isTrue);
    expect(factory.getProvider('custom'), same(custom));

    factory.unregisterProvider('custom');
    expect(factory.hasProvider('custom'), isFalse);
  });

  test('clearProviders empties the registry; resetToDefaults restores it', () {
    factory.clearProviders();
    expect(factory.getAvailableProviders(), isEmpty);

    factory.resetToDefaults();
    expect(factory.getAvailableProviders(), hasLength(5));
  });
}
