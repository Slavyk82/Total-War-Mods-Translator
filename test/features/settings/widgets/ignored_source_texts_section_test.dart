// Widget-level coverage for `IgnoredSourceTextsSection` — the expandable
// settings section that lists/manages ignored source texts. Exercises the
// rendered body (info banner + actions + datagrid), the empty/populated grid
// states, the add flow (editor dialog -> notifier.addText -> success/error
// toast), and the reset flow (confirm dialog -> notifier.resetToDefaults ->
// success/error toast).
//
// House rules: pump under ProviderScope via createThemedTestableWidget with
// AppTheme.atelierDarkTheme; surface 1200x1600 dPR 1.0 with tearDown resets;
// override both the count provider (accordion activeCount) and the texts
// provider (datagrid) with fake codegen notifiers; drain the 4s toast timer.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/providers/ignored_source_texts_providers.dart';
import 'package:twmt/features/settings/widgets/ignored_source_text_editor_dialog.dart';
import 'package:twmt/features/settings/widgets/ignored_source_texts_section.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/dialogs/token_confirm_dialog.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Fake notifier: short-circuits `build()` with crafted data and records the
/// add/reset calls so the action flows can be asserted without a real service.
class _FakeIgnored extends IgnoredSourceTexts {
  _FakeIgnored({
    this.texts = const <IgnoredSourceText>[],
    this.addResult = (true, null),
    this.resetResult = (true, null),
  });

  final List<IgnoredSourceText> texts;
  final (bool, String?) addResult;
  final (bool, String?) resetResult;

  final List<String> addedTexts = <String>[];
  int resetCalls = 0;

  @override
  Future<List<IgnoredSourceText>> build() async => texts;

  @override
  Future<(bool, String?)> addText(String sourceText) async {
    addedTexts.add(sourceText);
    return addResult;
  }

  @override
  Future<(bool, String?)> resetToDefaults() async {
    resetCalls++;
    return resetResult;
  }
}

IgnoredSourceText _text(String source) => IgnoredSourceText(
      id: 'id-$source',
      sourceText: source,
      createdAt: 0,
      updatedAt: 0,
    );

Future<void> _pump(
  WidgetTester tester, {
  required _FakeIgnored fake,
  int enabledCount = 0,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    createThemedTestableWidget(
      const Scaffold(
        body: SingleChildScrollView(child: IgnoredSourceTextsSection()),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        ignoredSourceTextsProvider.overrideWith(() => fake),
        enabledIgnoredTextsCountProvider.overrideWith((ref) async => enabledCount),
      ],
    ),
  );
  await tester.pumpAndSettle();
}

/// Expands the accordion so the body (info banner, actions, grid) builds.
Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.text(t.settings.ignoredTexts.accordionTitle));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders the collapsed header with the active-count pill',
      (tester) async {
    await _pump(tester, fake: _FakeIgnored(), enabledCount: 3);

    expect(find.text(t.settings.ignoredTexts.accordionTitle), findsOneWidget);
    // StatusPill text is built from the active count.
    expect(
      find.text(t.widgets.settingsAccordion.activeCount(count: 3)),
      findsOneWidget,
    );
  });

  testWidgets('expanding renders the body with info banner and action buttons',
      (tester) async {
    await _pump(
      tester,
      fake: _FakeIgnored(texts: [_text('placeholder')]),
    );
    await _expand(tester);

    expect(find.text(t.settings.ignoredTexts.infoText), findsOneWidget);
    expect(find.text(t.settings.ignoredTexts.addButton), findsOneWidget);
    expect(find.text(t.settings.ignoredTexts.resetButton), findsOneWidget);
  });

  testWidgets('shows the grid empty state when there are no texts',
      (tester) async {
    await _pump(tester, fake: _FakeIgnored());
    await _expand(tester);

    expect(find.text(t.settings.ignoredTexts.grid.emptyTitle), findsOneWidget);
  });

  testWidgets('add: opens the editor dialog, submits, calls notifier and '
      'shows the success toast', (tester) async {
    final fake = _FakeIgnored();
    await _pump(tester, fake: fake);
    await _expand(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.addButton));
    await tester.pumpAndSettle();
    expect(find.byType(IgnoredSourceTextEditorDialog), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'newtext');
    await tester.pump();
    // The dialog's "Add" submit button.
    await tester.tap(find.text(t.settings.ignoredTexts.editorDialog.add));
    await tester.pumpAndSettle();

    expect(fake.addedTexts, ['newtext']);
    expect(find.text(t.settings.ignoredTexts.toasts.addSuccess), findsOneWidget);

    // Drain the toast auto-dismiss timer.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('add: cancelled dialog does not call the notifier',
      (tester) async {
    final fake = _FakeIgnored();
    await _pump(tester, fake: fake);
    await _expand(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.addButton));
    await tester.pumpAndSettle();

    await tester.tap(find.text(t.settings.ignoredTexts.editorDialog.cancel));
    await tester.pumpAndSettle();

    expect(fake.addedTexts, isEmpty);
    expect(find.byType(IgnoredSourceTextEditorDialog), findsNothing);
  });

  testWidgets('add: failure surfaces the error message in a toast',
      (tester) async {
    final fake = _FakeIgnored(addResult: (false, 'duplicate'));
    await _pump(tester, fake: fake);
    await _expand(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.addButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'dup');
    await tester.pump();
    await tester.tap(find.text(t.settings.ignoredTexts.editorDialog.add));
    await tester.pumpAndSettle();

    expect(fake.addedTexts, ['dup']);
    expect(find.text('duplicate'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('reset: confirming calls notifier and shows the success toast',
      (tester) async {
    final fake = _FakeIgnored(texts: [_text('placeholder')]);
    await _pump(tester, fake: fake);
    await _expand(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.resetButton));
    await tester.pumpAndSettle();
    expect(find.byType(TokenConfirmDialog), findsOneWidget);

    await tester.tap(find.text(t.settings.ignoredTexts.resetDialog.confirmLabel));
    await tester.pumpAndSettle();

    expect(fake.resetCalls, 1);
    expect(
      find.text(t.settings.ignoredTexts.toasts.resetSuccess),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('reset: failure surfaces the error message in a toast',
      (tester) async {
    final fake = _FakeIgnored(resetResult: (false, 'reset boom'));
    await _pump(tester, fake: fake);
    await _expand(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.resetButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.settings.ignoredTexts.resetDialog.confirmLabel));
    await tester.pumpAndSettle();

    expect(fake.resetCalls, 1);
    expect(find.text('reset boom'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('reset: cancelling the confirm dialog does not call the notifier',
      (tester) async {
    final fake = _FakeIgnored(texts: [_text('placeholder')]);
    await _pump(tester, fake: fake);
    await _expand(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.resetButton));
    await tester.pumpAndSettle();
    expect(find.byType(TokenConfirmDialog), findsOneWidget);

    // TokenConfirmDialog renders a default 'Cancel' action that pops false.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.resetCalls, 0);
    expect(find.byType(TokenConfirmDialog), findsNothing);
  });
}
