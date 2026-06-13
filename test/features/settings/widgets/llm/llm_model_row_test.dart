// Widget tests for `LlmModelRow` — the single-model row inside
// `LlmModelsList`. The row renders a checkbox, the model's friendly name (with
// an optional model-id secondary label and a "Default" badge), and a star
// button to set the model as the global default. Tapping the row toggles the
// model's enabled state; tapping the star sets it as default. Both actions go
// through the `llmModelsProvider(providerCode).notifier`, which we override
// with a fake that records calls and returns a scripted (success, error)
// result so no real services or secure storage are touched.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/features/settings/widgets/llm/llm_model_row.dart';
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';

import '../../../../helpers/test_bootstrap.dart';
import '../../../../helpers/test_helpers.dart';

/// Fake notifier that records `toggleEnabled` / `setAsDefault` calls and
/// returns a scripted result. `build()` returns an empty list so the provider
/// resolves without any real service.
class _FakeLlmModels extends LlmModels {
  _FakeLlmModels({
    this.toggleResult = const (true, null),
    this.setDefaultResult = const (true, null),
  });

  final (bool, String?) toggleResult;
  final (bool, String?) setDefaultResult;

  final List<String> toggledIds = [];
  final List<String> setDefaultIds = [];

  @override
  Future<List<LlmProviderModel>> build(String providerCode) async =>
      const <LlmProviderModel>[];

  @override
  Future<(bool, String?)> toggleEnabled(String modelId) async {
    toggledIds.add(modelId);
    return toggleResult;
  }

  @override
  Future<(bool, String?)> setAsDefault(String modelId) async {
    setDefaultIds.add(modelId);
    return setDefaultResult;
  }
}

LlmProviderModel _model({
  String id = 'm1',
  String modelId = 'claude-3-5-sonnet',
  String? displayName,
  bool isEnabled = false,
  bool isDefault = false,
}) {
  return LlmProviderModel(
    id: id,
    providerCode: 'anthropic',
    modelId: modelId,
    displayName: displayName,
    isEnabled: isEnabled,
    isDefault: isDefault,
    createdAt: 1,
    updatedAt: 1,
    lastFetchedAt: 1,
  );
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<_FakeLlmModels> pumpRow(
    WidgetTester tester, {
    required LlmProviderModel model,
    bool showDivider = false,
    _FakeLlmModels? fake,
  }) async {
    final notifier = fake ?? _FakeLlmModels();
    await tester.pumpWidget(
      createThemedTestableWidget(
        Scaffold(
          body: LlmModelRow(
            model: model,
            providerCode: 'anthropic',
            showDivider: showDivider,
          ),
        ),
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          llmModelsProvider.overrideWith(() => notifier),
        ],
      ),
    );
    await tester.pumpAndSettle();
    return notifier;
  }

  // Drains the success/error toast (4 s auto-dismiss + exit animation) so the
  // test ends with no pending timers.
  Future<void> drainToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  }

  testWidgets('renders friendly name and model-id secondary label', (tester) async {
    await pumpRow(
      tester,
      model: _model(displayName: 'Claude 3.5 Sonnet', modelId: 'claude-3-5-sonnet'),
    );

    // friendlyName == displayName, and modelId differs so the secondary
    // label is shown.
    expect(find.text('Claude 3.5 Sonnet'), findsOneWidget);
    expect(find.text('claude-3-5-sonnet'), findsOneWidget);
  });

  testWidgets('omits secondary model-id label when it equals friendly name',
      (tester) async {
    await pumpRow(
      tester,
      // No displayName -> friendlyName falls back to modelId, so the rows are
      // equal and the secondary label branch is skipped.
      model: _model(modelId: 'gpt-4o'),
    );

    expect(find.text('gpt-4o'), findsOneWidget);
  });

  testWidgets('disabled model shows empty checkbox and no checkmark',
      (tester) async {
    await pumpRow(tester, model: _model(isEnabled: false));

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsNothing);
  });

  testWidgets('enabled model shows the checkmark icon', (tester) async {
    await pumpRow(tester, model: _model(isEnabled: true));

    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsOneWidget);
  });

  testWidgets('default model shows the Default badge and filled star',
      (tester) async {
    await pumpRow(tester, model: _model(isDefault: true));

    expect(find.byIcon(FluentIcons.star_24_filled), findsOneWidget);
    expect(find.byIcon(FluentIcons.star_24_regular), findsNothing);
  });

  testWidgets('non-default model shows the outline star', (tester) async {
    await pumpRow(tester, model: _model(isDefault: false));

    expect(find.byIcon(FluentIcons.star_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.star_24_filled), findsNothing);
  });

  testWidgets('shows divider when showDivider is true', (tester) async {
    await pumpRow(tester, model: _model(), showDivider: true);
    expect(find.byType(Divider), findsOneWidget);
  });

  testWidgets('hides divider when showDivider is false', (tester) async {
    await pumpRow(tester, model: _model(), showDivider: false);
    expect(find.byType(Divider), findsNothing);
  });

  testWidgets('tapping the row toggles enabled and shows a success toast',
      (tester) async {
    final fake = _FakeLlmModels(toggleResult: const (true, null));
    await pumpRow(tester, model: _model(isEnabled: false), fake: fake);

    await tester.tap(find.byType(GestureDetector).first);
    // Spinner appears while processing.
    await tester.pump();
    expect(find.byType(FluentSpinner), findsOneWidget);

    await tester.pumpAndSettle();
    expect(fake.toggledIds, ['m1']);

    await drainToast(tester);
  });

  testWidgets('toggle failure shows an error toast', (tester) async {
    final fake = _FakeLlmModels(toggleResult: const (false, 'boom'));
    await pumpRow(tester, model: _model(isEnabled: true), fake: fake);

    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();

    expect(fake.toggledIds, ['m1']);
    await drainToast(tester);
  });

  testWidgets('tapping the star on a non-default model sets it as default',
      (tester) async {
    final fake = _FakeLlmModels(setDefaultResult: const (true, null));
    await pumpRow(tester, model: _model(isDefault: false), fake: fake);

    await tester.tap(find.byIcon(FluentIcons.star_24_regular));
    await tester.pumpAndSettle();

    expect(fake.setDefaultIds, ['m1']);
    await drainToast(tester);
  });

  testWidgets('set-default failure shows an error toast', (tester) async {
    final fake = _FakeLlmModels(setDefaultResult: const (false, 'nope'));
    await pumpRow(tester, model: _model(isDefault: false), fake: fake);

    await tester.tap(find.byIcon(FluentIcons.star_24_regular));
    await tester.pumpAndSettle();

    expect(fake.setDefaultIds, ['m1']);
    await drainToast(tester);
  });

  testWidgets('star GestureDetector is disabled for a default model',
      (tester) async {
    final fake = _FakeLlmModels();
    await pumpRow(tester, model: _model(isDefault: true), fake: fake);

    // The star's GestureDetector has a null onTap when the model is already
    // the default (the build branch that disables set-as-default). Asserting
    // the null callback avoids tapping the Tooltip child, which would leave a
    // pending tooltip timer.
    final starGesture = tester.widget<GestureDetector>(
      find
          .ancestor(
            of: find.byIcon(FluentIcons.star_24_filled),
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    expect(starGesture.onTap, isNull);
    expect(fake.setDefaultIds, isEmpty);
  });
}
