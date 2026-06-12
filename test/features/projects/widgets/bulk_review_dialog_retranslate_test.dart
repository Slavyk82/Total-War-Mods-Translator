// Regression tests for the per-row retranslate action of [BulkReviewDialog].
//
// 2026-06-10 review (LOW / L10): the dialog's private _resolveProviderModel
// claimed to mirror bulk_operations_handlers' _resolveSelectedProvider but
// omitted its `active_llm_provider` fallback. A user with an active LLM
// provider configured in settings but no model selected in the editor could
// run bulk "Translate all"/"Retranslate all" successfully, yet every per-row
// retranslate button in the same review dialog failed with the
// "no model selected" error. These tests lock in the mirrored contract:
//   - no editor model + active provider set => runner invoked with
//     providerId 'provider_<code>' and a null modelId;
//   - no editor model + no active provider => error surfaced, runner not
//     invoked.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_review_rows_provider.dart';
import 'package:twmt/features/projects/widgets/bulk_review_dialog.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/features/translation_editor/providers/llm_model_providers.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/services/translation/headless_batch_translation_runner.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

class _MockRunner extends Mock implements HeadlessBatchTranslationRunner {}

/// Editor model selection stubbed to "nothing selected" (the state of a user
/// who never opened the editor's model selector).
class _NoSelectionLlmModel extends SelectedLlmModel {
  @override
  String? build() => null;
}

/// LLM provider settings stubbed to a fixed map (no settings service needed).
class _StubLlmProviderSettings extends LlmProviderSettings {
  _StubLlmProviderSettings(this._settings);
  final Map<String, String> _settings;

  @override
  Future<Map<String, String>> build() async => _settings;
}

/// Drains RenderFlex-overflow exceptions originating from [TokenDialog]'s
/// footer Row. The wide Ahem glyphs used by the test font make the dialog's
/// three footer buttons ~15px wider than the 760px dialog; production fonts
/// fit. Mirrors the `_drainOverflowExceptions` pattern in
/// navigation_sidebar_test.dart: anything that is not a token_dialog overflow
/// re-throws so unrelated failures stay loud.
void _drainTokenDialogOverflow(WidgetTester tester) {
  while (true) {
    final e = tester.takeException();
    if (e == null) return;
    final msg = e.toString();
    // The taken exception's toString carries only the overflow message, not
    // the creator chain, so match on the bare prefix (same fallback as the
    // sidebar test).
    if (msg.contains('A RenderFlex overflowed')) continue;
    if (msg.startsWith('Multiple exceptions')) continue;
    throw e;
  }
}

const _row = BulkReviewRow(
  projectId: 'proj-1',
  projectName: 'My project',
  projectLanguageId: 'pl-1',
  unitId: 'unit-1',
  versionId: 'v-1',
  key: 'unit_key',
  sourceText: 'Hello',
  translatedText: 'Bonjour',
);

void main() {
  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  late _MockRunner runner;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    runner = _MockRunner();
    when(() => runner.run(
          projectLanguageId: any(named: 'projectLanguageId'),
          projectId: any(named: 'projectId'),
          unitIds: any(named: 'unitIds'),
          skipTM: any(named: 'skipTM'),
          providerId: any(named: 'providerId'),
          modelId: any(named: 'modelId'),
        )).thenAnswer((_) async => 1);
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Map<String, String> llmSettings,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const Scaffold(body: BulkReviewDialog()),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        bulkReviewRowsProvider.overrideWith((ref) async => [_row]),
        selectedLlmModelProvider.overrideWith(_NoSelectionLlmModel.new),
        llmProviderSettingsProvider
            .overrideWith(() => _StubLlmProviderSettings(llmSettings)),
        headlessBatchTranslationRunnerProvider.overrideWithValue(runner),
      ],
    ));
    await tester.pumpAndSettle();
    _drainTokenDialogOverflow(tester);
  }

  testWidgets(
      'per-row retranslate falls back to the active_llm_provider setting '
      'when no editor model is selected', (tester) async {
    await pumpDialog(
      tester,
      llmSettings: {SettingsKeys.activeProvider: 'anthropic'},
    );

    await tester.tap(
      find.byTooltip(t.projects.bulk.review.tooltipRetranslate),
    );
    await tester.pumpAndSettle();

    verify(() => runner.run(
          projectLanguageId: 'pl-1',
          projectId: 'proj-1',
          unitIds: any(named: 'unitIds'),
          skipTM: true,
          providerId: 'provider_anthropic',
          modelId: null,
        )).called(1);
    expect(find.text(t.projects.bulk.review.noModelSelected), findsNothing);
  });

  testWidgets(
      'per-row retranslate still reports "no model selected" when neither a '
      'model nor an active provider is configured', (tester) async {
    await pumpDialog(tester, llmSettings: const {});

    await tester.tap(
      find.byTooltip(t.projects.bulk.review.tooltipRetranslate),
    );
    await tester.pumpAndSettle();

    verifyNever(() => runner.run(
          projectLanguageId: any(named: 'projectLanguageId'),
          projectId: any(named: 'projectId'),
          unitIds: any(named: 'unitIds'),
          skipTM: any(named: 'skipTM'),
          providerId: any(named: 'providerId'),
          modelId: any(named: 'modelId'),
        ));
    expect(find.text(t.projects.bulk.review.noModelSelected), findsOneWidget);
  });
}
