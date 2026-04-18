// Golden tests for the Settings screen - LLM Providers tab (Plan 5e - Task 8).
//
// The LLM Providers tab gates on `llmProviderSettingsProvider` and renders
// five collapsed accordion sections (one per provider) plus the custom
// rules accordion. Collapsed accordions don't build their bodies, so the
// per-provider `llmModelsProvider(code)` family is never hit; we only need
// to override the two settings-map providers and the two badge-count
// providers that the headers read eagerly.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/llm_custom_rules_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Minimal LLM-settings fixture: empty API keys, a stable rate-limit value
/// so the slider's thumb lands in the same spot across runs.
class _FakeLlmProviderSettings extends LlmProviderSettings {
  @override
  Future<Map<String, String>> build() async => const <String, String>{
        SettingsKeys.activeProvider: 'openai',
        SettingsKeys.anthropicModel: '',
        SettingsKeys.anthropicApiKey: '',
        SettingsKeys.openaiModel: '',
        SettingsKeys.openaiApiKey: '',
        SettingsKeys.deeplPlan: 'free',
        SettingsKeys.deeplApiKey: '',
        SettingsKeys.deepseekApiKey: '',
        SettingsKeys.geminiApiKey: '',
        SettingsKeys.rateLimit: '500',
      };
}

/// Empty rule list — custom-rules accordion stays collapsed, but the
/// provider still resolves so the badge count can read 0.
class _FakeLlmCustomRules extends LlmCustomRules {
  @override
  Future<List<LlmCustomRule>> build() async => const <LlmCustomRule>[];
}

List<Override> _overrides() => [
      llmProviderSettingsProvider.overrideWith(_FakeLlmProviderSettings.new),
      llmCustomRulesProvider.overrideWith(_FakeLlmCustomRules.new),
      enabledRulesCountProvider.overrideWith((_) async => 0),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SettingsScreen(),
      theme: theme,
      overrides: _overrides(),
    ));
    await tester.pumpAndSettle();

    // LLM Providers is the 3rd tab (index 2).
    await tester.tap(find.text('LLM Providers'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings llm providers atelier', (tester) async {
    await pumpUnder(tester, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_llm_providers_atelier.png'),
    );
  });

  testWidgets('settings llm providers forge', (tester) async {
    await pumpUnder(tester, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(SettingsScreen),
      matchesGoldenFile('../goldens/settings_llm_providers_forge.png'),
    );
  });
}
