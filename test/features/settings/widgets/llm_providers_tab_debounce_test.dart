// Regression test for Plan 5f Task 7: the rate-limit slider's `onChanged`
// must debounce bursts (full drags emit up to 49 events with
// `divisions: 49`, `min: 10`, `max: 500`) into a single provider write.
//
// Strategy: override `llmProviderSettingsProvider` with a fake notifier
// that counts `updateRateLimit` calls, pump the `LlmProvidersTab`, drive
// the Slider's `onChanged` directly (found via the widget tree rather
// than through gesture geometry, which is fragile for ranged sliders),
// then advance past the 300ms debounce and assert exactly one write.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/llm_custom_rules_providers.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/features/settings/widgets/llm_providers_tab.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Fake notifier that counts `updateRateLimit` calls and short-circuits
/// `build()` so no real settings service or secure storage is hit.
class _FakeLlmProviderSettings extends LlmProviderSettings {
  int rateLimitWriteCount = 0;

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

  @override
  Future<void> updateRateLimit(int limit) async {
    rateLimitWriteCount += 1;
  }
}

/// Empty custom-rules list so the accordion resolves cleanly.
class _FakeLlmCustomRules extends LlmCustomRules {
  @override
  Future<List<LlmCustomRule>> build() async => const <LlmCustomRule>[];
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
    'rate-limit slider debounces bursts to a single write',
    (tester) async {
      final fake = _FakeLlmProviderSettings();

      await tester.pumpWidget(
        createThemedTestableWidget(
          const Scaffold(body: LlmProvidersTab()),
          theme: AppTheme.atelierDarkTheme,
          overrides: [
            llmProviderSettingsProvider.overrideWith(() => fake),
            llmCustomRulesProvider.overrideWith(_FakeLlmCustomRules.new),
            enabledRulesCountProvider.overrideWith((_) async => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // The slider sits near the bottom of a ListView — scroll the list
      // until the slider builds.
      await tester.scrollUntilVisible(
        find.byType(Slider),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Grab the live Slider widget and drive its `onChanged` directly —
      // this bypasses the brittle drag geometry required to make a real
      // Slider emit `onChanged`, while still exercising the exact
      // callback the widget installs.
      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.onChanged, isNotNull);

      // Simulate a 49-tick drag from 500 -> 10.
      for (int i = 0; i < 49; i++) {
        slider.onChanged!.call(500 - (i * 10).toDouble());
      }
      // Between bursts we pump far less than the 300ms debounce so the
      // Timer keeps getting cancelled and rescheduled.
      await tester.pump(const Duration(milliseconds: 50));

      // No writes yet — still inside the debounce window.
      expect(fake.rateLimitWriteCount, 0);

      // Advance past 300ms so the final Timer fires.
      await tester.pump(const Duration(milliseconds: 350));
      // Let the async body complete.
      await tester.pump();

      expect(
        fake.rateLimitWriteCount,
        1,
        reason:
            '49 onChanged events within 300ms should collapse to 1 provider write',
      );
    },
  );

  testWidgets(
    'rate-limit slider only writes once even after many rapid changes',
    (tester) async {
      // Weaker safety-net assertion: even if the debounce window is tuned,
      // we must not regress to N writes for N bursts.
      final fake = _FakeLlmProviderSettings();

      await tester.pumpWidget(
        createThemedTestableWidget(
          const Scaffold(body: LlmProvidersTab()),
          theme: AppTheme.atelierDarkTheme,
          overrides: [
            llmProviderSettingsProvider.overrideWith(() => fake),
            llmCustomRulesProvider.overrideWith(_FakeLlmCustomRules.new),
            enabledRulesCountProvider.overrideWith((_) async => 0),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byType(Slider),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final slider = tester.widget<Slider>(find.byType(Slider));
      for (int i = 0; i < 10; i++) {
        slider.onChanged!.call(100 + i.toDouble());
        await tester.pump(const Duration(milliseconds: 10));
      }

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(fake.rateLimitWriteCount, lessThan(10));
      expect(fake.rateLimitWriteCount, greaterThanOrEqualTo(1));
    },
  );
}
