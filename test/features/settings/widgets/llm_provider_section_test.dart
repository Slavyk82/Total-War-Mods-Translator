// Regression test for the 2026-06-09 review finding L8: clicking the
// "Test connection" button right after typing an API key used to race the
// 600 ms debounced save — `testConnection` reads the key from secure
// storage, so it validated the stale stored key (or reported
// 'No API key configured' on first-time setup) instead of the key in the
// field. The fix cancels the pending debounce and awaits `onSaveApiKey()`
// before running the test.
//
// Strategy (mirrors llm_providers_tab_debounce_test.dart): override
// `llmProviderSettingsProvider` with a fake notifier whose
// `testConnection` records how many saves had completed at test time, pump
// a single `LlmProviderSection`, type into the API-key field, and click
// Test inside the debounce window.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/features/settings/widgets/llm_provider_section.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Fake notifier that records `testConnection` calls and short-circuits
/// `build()` so no real settings service or secure storage is hit.
class _FakeLlmProviderSettings extends LlmProviderSettings {
  _FakeLlmProviderSettings(this.onTestConnection);

  final void Function(String providerCode) onTestConnection;

  @override
  Future<Map<String, String>> build() async => const <String, String>{};

  @override
  Future<(bool, String?)> testConnection(String providerCode) async {
    onTestConnection(providerCode);
    return (true, null);
  }
}

/// Empty models list so `LlmModelsList` resolves without services.
class _FakeLlmModels extends LlmModels {
  @override
  Future<List<LlmProviderModel>> build(String providerCode) async =>
      const <LlmProviderModel>[];
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<TextEditingController> pumpSection(
    WidgetTester tester, {
    required Future<void> Function() onSaveApiKey,
    required _FakeLlmProviderSettings fake,
  }) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      createThemedTestableWidget(
        Scaffold(
          body: SingleChildScrollView(
            child: LlmProviderSection(
              providerCode: 'anthropic',
              providerName: 'Anthropic',
              apiKeyController: controller,
              onSaveApiKey: onSaveApiKey,
            ),
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          llmProviderSettingsProvider.overrideWith(() => fake),
          llmModelsProvider.overrideWith(_FakeLlmModels.new),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Expand the accordion so the API-key field and Test button build.
    await tester.tap(find.text('Anthropic'));
    await tester.pumpAndSettle();

    return controller;
  }

  // The accordion header and the Test button share the same icon; the
  // button's icon is built after the header, so `.last` targets the button.
  Finder testButton() =>
      find.byIcon(FluentIcons.plug_connected_24_regular).last;

  testWidgets(
    'Test connection flushes the pending debounced save before testing',
    (tester) async {
      var saveCount = 0;
      int? saveCountAtTest;

      final fake = _FakeLlmProviderSettings(
        (_) => saveCountAtTest = saveCount,
      );

      await pumpSection(
        tester,
        fake: fake,
        onSaveApiKey: () async {
          // Simulate the parent's async secure-storage write.
          await Future<void>.delayed(Duration.zero);
          saveCount += 1;
        },
      );

      await tester.enterText(find.byType(TextField), 'sk-new-key');
      // Still inside the 600 ms debounce window — nothing saved yet.
      await tester.pump(const Duration(milliseconds: 100));
      expect(saveCount, 0);

      await tester.tap(testButton());
      // Let the flushed save (zero-delay future) and testConnection run.
      // Duration pumps are needed so the fake clock fires the save's timer.
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 1));

      expect(
        saveCountAtTest,
        1,
        reason: 'testConnection must run only after the API-key save '
            'completed, so it validates the key currently in the field',
      );

      // The pending debounce was cancelled — no duplicate save fires later.
      await tester.pump(const Duration(seconds: 1));
      expect(saveCount, 1);

      // Drain the success toast (4 s auto-dismiss + exit animation).
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'typing alone still debounces to a single save and never tests',
    (tester) async {
      var saveCount = 0;
      var testCount = 0;

      final fake = _FakeLlmProviderSettings((_) => testCount += 1);

      await pumpSection(
        tester,
        fake: fake,
        onSaveApiKey: () async {
          saveCount += 1;
        },
      );

      await tester.enterText(find.byType(TextField), 'sk-a');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'sk-ab');
      await tester.pump(const Duration(milliseconds: 200));
      expect(saveCount, 0, reason: 'still inside the debounce window');

      await tester.pump(const Duration(milliseconds: 700));
      expect(saveCount, 1,
          reason: 'rapid edits must collapse to one save after 600 ms idle');
      expect(testCount, 0);
    },
  );
}
