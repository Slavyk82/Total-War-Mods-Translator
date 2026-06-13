// Widget tests for `EditorToolbarModelSelector` — the inline LLM model dropdown
// rendered in the translation editor sidebar.
//
// The selector watches three providers:
//   * `availableLlmModelsProvider` — the list of enabled, non-archived models;
//   * `selectedLlmModelProvider`   — the currently selected model id (nullable);
//   * `llmProviderSettingsProvider`— settings, used only for the active provider.
//
// It renders an `_TriggerButton` showing `providerCode: friendlyName` (or just
// the friendly name in compact mode), opens a `MenuAnchor` listing every model
// as a `_ModelMenuItem`, and writes the chosen id back through
// `selectedLlmModelProvider.notifier.setModel`. When the list is empty it
// collapses to a `SizedBox.shrink`, while the loading state shows a
// `LinearProgressIndicator`.
//
// We override all three providers with crafted fakes (no real services or
// repositories), assert what is rendered, open the menu, select a model and
// verify the notifier recorded the call.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:twmt/models/domain/llm_provider_model.dart';
import 'package:twmt/providers/editor_providers.dart';
import 'package:twmt/providers/settings_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/translation/editor_toolbar_model_selector.dart';

import '../../helpers/test_bootstrap.dart';
import '../../helpers/test_helpers.dart';

/// Fake [SelectedLlmModel] notifier. `build()` returns [initial] (no async
/// hydration / settings access) and `setModel` / `seedDefaultIfEmpty` record
/// their arguments so tests can assert the selection wiring fired.
class _FakeSelectedLlmModel extends SelectedLlmModel {
  _FakeSelectedLlmModel({this.initial});

  final String? initial;

  final List<String?> setIds = [];
  final List<String> seededIds = [];

  @override
  String? build() => initial;

  @override
  void setModel(String? modelId) {
    setIds.add(modelId);
    state = modelId;
  }

  @override
  void seedDefaultIfEmpty(String modelId) {
    // Record only — deliberately do NOT mutate state. The production seeder
    // mutates state, but for tests that exercise `_findBestDefaultModel`'s
    // resolution branches we want the (async) settings to drive the final
    // rendered model rather than freezing on whatever the first build (with
    // settings still loading) picked.
    seededIds.add(modelId);
  }
}

/// Fake [LlmProviderSettings] notifier returning a fixed active-provider map
/// without touching the settings service or secure storage.
class _FakeLlmProviderSettings extends LlmProviderSettings {
  _FakeLlmProviderSettings(this.activeProvider);

  final String activeProvider;

  @override
  Future<Map<String, String>> build() async => {
        SettingsKeys.activeProvider: activeProvider,
      };
}

LlmProviderModel _model({
  required String id,
  String providerCode = 'openai',
  String? modelId,
  String? displayName,
  bool isDefault = false,
  bool isEnabled = true,
}) {
  return LlmProviderModel(
    id: id,
    providerCode: providerCode,
    modelId: modelId ?? id,
    displayName: displayName,
    isEnabled: isEnabled,
    isDefault: isDefault,
    createdAt: 1,
    updatedAt: 1,
    lastFetchedAt: 1,
  );
}

void main() {
  const surface = Size(1200, 1600);

  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  /// Pumps the selector with crafted providers. Returns the fake selection
  /// notifier so tests can assert recorded calls.
  Future<_FakeSelectedLlmModel> pumpSelector(
    WidgetTester tester, {
    required FutureOr<List<LlmProviderModel>> models,
    String? selectedId,
    String activeProvider = '',
    bool compact = false,
    bool settle = true,
  }) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final selected = _FakeSelectedLlmModel(initial: selectedId);
    final overrides = <Override>[
      availableLlmModelsProvider.overrideWith((ref) => models),
      selectedLlmModelProvider.overrideWith(() => selected),
      llmProviderSettingsProvider
          .overrideWith(() => _FakeLlmProviderSettings(activeProvider)),
    ];

    await tester.pumpWidget(
      createThemedTestableWidget(
        Scaffold(body: EditorToolbarModelSelector(compact: compact)),
        theme: AppTheme.atelierDarkTheme,
        overrides: overrides,
        screenSize: surface,
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    }
    return selected;
  }

  testWidgets('loading state shows a LinearProgressIndicator', (tester) async {
    // A never-completing future keeps the provider in the loading branch.
    final completer = Completer<List<LlmProviderModel>>();
    await pumpSelector(tester, models: completer.future, settle: false);
    await tester.pump();

    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let the future complete with empty so no pending timers remain.
    completer.complete(const <LlmProviderModel>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('error state renders nothing (SizedBox.shrink)',
      (tester) async {
    tester.view.physicalSize = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Throwing synchronously inside the override drives the provider into its
    // error branch (the function-based provider rethrows into the AsyncValue).
    await tester.pumpWidget(
      createThemedTestableWidget(
        const Scaffold(body: EditorToolbarModelSelector()),
        theme: AppTheme.atelierDarkTheme,
        overrides: <Override>[
          availableLlmModelsProvider.overrideWith(
            (ref) => throw Exception('boom'),
          ),
          selectedLlmModelProvider
              .overrideWith(() => _FakeSelectedLlmModel(initial: null)),
          llmProviderSettingsProvider
              .overrideWith(() => _FakeLlmProviderSettings('')),
        ],
        screenSize: surface,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MenuAnchor), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byIcon(FluentIcons.brain_circuit_24_regular), findsNothing);
  });

  testWidgets('empty model list renders nothing (SizedBox.shrink)',
      (tester) async {
    await pumpSelector(tester, models: const <LlmProviderModel>[]);

    expect(find.byType(MenuAnchor), findsNothing);
    expect(find.byIcon(FluentIcons.brain_circuit_24_regular), findsNothing);
  });

  testWidgets('renders trigger label as "providerCode: friendlyName"',
      (tester) async {
    await pumpSelector(
      tester,
      models: [
        _model(
          id: 'm1',
          providerCode: 'openai',
          displayName: 'GPT-4o',
        ),
      ],
      selectedId: 'm1',
    );

    expect(find.text('openai: GPT-4o'), findsOneWidget);
    expect(find.byIcon(FluentIcons.brain_circuit_24_regular), findsWidgets);
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
  });

  testWidgets('compact mode renders only the friendly name', (tester) async {
    await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
      ],
      selectedId: 'm1',
      compact: true,
    );

    expect(find.text('GPT-4o'), findsOneWidget);
    expect(find.text('openai: GPT-4o'), findsNothing);
  });

  testWidgets('opens the menu listing every available model', (tester) async {
    await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
        _model(id: 'm2', providerCode: 'anthropic', displayName: 'Sonnet'),
      ],
      selectedId: 'm1',
    );

    await tester.tap(find.byType(EditorToolbarModelSelector));
    await tester.pumpAndSettle();

    // Both rows render their "providerCode: friendlyName" label.
    expect(find.text('openai: GPT-4o'), findsWidgets);
    expect(find.text('anthropic: Sonnet'), findsOneWidget);
    // Selected row shows the checkmark; the other shows the brain icon.
    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsOneWidget);
  });

  testWidgets('arrow flips to up while the menu is open', (tester) async {
    await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
      ],
      selectedId: 'm1',
    );

    await tester.tap(find.byType(EditorToolbarModelSelector));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.arrow_drop_up_rounded), findsOneWidget);

    // Tapping the trigger again closes the menu (controller.close branch).
    await tester.tap(find.byType(EditorToolbarModelSelector));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
  });

  testWidgets('selecting a different model calls setModel with its id',
      (tester) async {
    final selected = await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
        _model(id: 'm2', providerCode: 'anthropic', displayName: 'Sonnet'),
      ],
      selectedId: 'm1',
    );

    await tester.tap(find.byType(EditorToolbarModelSelector));
    await tester.pumpAndSettle();

    await tester.tap(find.text('anthropic: Sonnet'));
    await tester.pumpAndSettle();

    expect(selected.setIds, ['m2']);
  });

  testWidgets(
      'with no selection, seeds the provider default model id post-frame',
      (tester) async {
    // active provider 'anthropic' has a default model -> priority 1 path.
    final selected = await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
        _model(
          id: 'm2',
          providerCode: 'anthropic',
          displayName: 'Sonnet',
          isDefault: true,
        ),
      ],
      activeProvider: 'anthropic',
    );

    // Post-frame seed fired (the exact id can reflect the first build before
    // settings resolved, so we only assert a seed occurred).
    expect(selected.seededIds, isNotEmpty);
    // After settings resolve, the trigger reflects the active-provider default.
    expect(find.text('anthropic: Sonnet'), findsOneWidget);
  });

  testWidgets('default-model resolution falls back to enabled active-provider '
      'model when no provider default exists', (tester) async {
    final selected = await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
        _model(id: 'm2', providerCode: 'anthropic', displayName: 'Sonnet'),
      ],
      activeProvider: 'anthropic',
    );

    // No anthropic default -> first anthropic model (m2) is rendered once
    // settings resolve.
    expect(selected.seededIds, isNotEmpty);
    expect(find.text('anthropic: Sonnet'), findsOneWidget);
  });

  testWidgets('default-model resolution falls back to any default across '
      'providers when active provider has none', (tester) async {
    final selected = await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
        _model(
          id: 'm2',
          providerCode: 'anthropic',
          displayName: 'Sonnet',
          isDefault: true,
        ),
      ],
      // active provider 'deepl' has no models at all.
      activeProvider: 'deepl',
    );

    // No deepl model -> any default across providers (m2).
    expect(selected.seededIds, isNotEmpty);
    expect(find.text('anthropic: Sonnet'), findsOneWidget);
  });

  testWidgets('default-model resolution falls back to first model when no '
      'defaults and no active provider', (tester) async {
    final selected = await pumpSelector(
      tester,
      models: [
        _model(id: 'm1', providerCode: 'openai', displayName: 'GPT-4o'),
        _model(id: 'm2', providerCode: 'anthropic', displayName: 'Sonnet'),
      ],
      // empty active provider -> skip provider-specific branches entirely.
      activeProvider: '',
    );

    expect(selected.seededIds, ['m1']);
    expect(find.text('openai: GPT-4o'), findsOneWidget);
  });

  testWidgets('stale selected id (not in list) resolves to best default',
      (tester) async {
    // selectedId points at a model that is not present, so currentModel falls
    // back through _findBestDefaultModel (orElse branch).
    final selected = await pumpSelector(
      tester,
      models: [
        _model(
          id: 'm1',
          providerCode: 'openai',
          displayName: 'GPT-4o',
          isDefault: true,
        ),
      ],
      selectedId: 'gone',
      activeProvider: 'openai',
    );

    // A non-null selection means the seed path is skipped.
    expect(selected.seededIds, isEmpty);
    expect(find.text('openai: GPT-4o'), findsOneWidget);
  });
}
