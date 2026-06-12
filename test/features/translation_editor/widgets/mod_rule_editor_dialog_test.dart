import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/mod_rule_editor_dialog.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/providers/llm_custom_rules_providers.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

const _projectId = 'project-1';

LlmCustomRule _rule({String text = 'do not translate names', bool enabled = true}) =>
    LlmCustomRule(
      id: 'rule-1',
      ruleText: text,
      isEnabled: enabled,
      projectId: _projectId,
      createdAt: 0,
      updatedAt: 0,
    );

/// Fakes the project-custom-rule AsyncNotifier: drives build() to a value /
/// loading / error and records mutation calls without hitting the service.
class _FakeNotifier extends ProjectCustomRuleNotifier {
  _FakeNotifier({
    this.rule,
    this.loading = false,
    this.error,
    this.setResult = (true, null),
  });

  final LlmCustomRule? rule;
  final bool loading;
  final Object? error;
  final (bool, String?) setResult;

  String? lastSetText;
  int deleteCalls = 0;
  int toggleCalls = 0;

  @override
  Future<LlmCustomRule?> build(String projectId) async {
    if (loading) return Completer<LlmCustomRule?>().future;
    if (error != null) throw error!;
    return rule;
  }

  @override
  Future<(bool, String?)> setRule(String ruleText) async {
    lastSetText = ruleText;
    return setResult;
  }

  @override
  Future<(bool, String?)> deleteRule() async {
    deleteCalls++;
    return (true, null);
  }

  @override
  Future<(bool, String?)> toggleEnabled() async {
    toggleCalls++;
    return (true, null);
  }
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = const Size(1200, 1400);
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  // Host the dialog under a nested Navigator+Overlay so FluentToast's
  // Overlay.of(Navigator.context) resolves (see widget-test scaffolding notes).
  Future<void> pumpDialog(
    WidgetTester tester,
    _FakeNotifier fake, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Navigator(
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (navContext) => Center(
                  child: ElevatedButton(
                    onPressed: () => showDialog<void>(
                      context: navContext,
                      useRootNavigator: false,
                      builder: (_) => const ModRuleEditorDialog(
                        projectId: _projectId,
                        projectName: 'My Mod',
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        projectCustomRuleProvider(_projectId).overrideWith(() => fake),
      ],
    ));
    await tester.tap(find.text('open'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // The infinite spinner means pumpAndSettle would never converge; pump
      // the dialog entrance animation by a fixed amount instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  testWidgets('shows a spinner while the rule is loading', (tester) async {
    await pumpDialog(tester, _FakeNotifier(loading: true), settle: false);

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows an error message when loading fails', (tester) async {
    await pumpDialog(tester, _FakeNotifier(error: 'db down'));

    expect(find.textContaining('Error loading rule'), findsOneWidget);
  });

  testWidgets('prefills the rule text and shows delete + toggle for an existing rule',
      (tester) async {
    await pumpDialog(tester, _FakeNotifier(rule: _rule(text: 'keep names')));

    expect(find.text('Mod Translation Rule'), findsOneWidget);
    expect(find.text('My Mod'), findsOneWidget);
    expect(find.text('keep names'), findsOneWidget); // prefilled controller
    expect(find.text('Rule is active'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('hides delete + toggle when there is no existing rule',
      (tester) async {
    await pumpDialog(tester, _FakeNotifier());

    expect(find.text('Mod Translation Rule'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Rule is active'), findsNothing);
  });

  testWidgets('saving empty text shows a validation error and does not persist',
      (tester) async {
    final fake = _FakeNotifier();
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter a rule text'), findsOneWidget);
    expect(fake.lastSetText, isNull);
  });

  testWidgets('saving a valid rule persists it, closes and toasts',
      (tester) async {
    final fake = _FakeNotifier();
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), '  no translate  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(fake.lastSetText, 'no translate'); // trimmed
    expect(find.text('Mod Translation Rule'), findsNothing); // dialog popped
    expect(find.text('Mod rule saved successfully'), findsOneWidget); // toast

    await tester.pump(const Duration(seconds: 5)); // drain toast timer
    await tester.pumpAndSettle();
  });

  testWidgets('a failed save keeps the dialog open and toasts the error',
      (tester) async {
    final fake = _FakeNotifier(setResult: (false, 'write conflict'));
    await pumpDialog(tester, fake);

    await tester.enterText(find.byType(TextField), 'a rule');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Mod Translation Rule'), findsOneWidget); // still open
    expect(find.text('write conflict'), findsOneWidget); // error toast

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('tapping the toggle invokes toggleEnabled', (tester) async {
    final fake = _FakeNotifier(rule: _rule(enabled: true));
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Rule is active'));
    await tester.pumpAndSettle();

    expect(fake.toggleCalls, 1);
  });

  testWidgets('confirming the delete dialog deletes the rule and closes',
      (tester) async {
    final fake = _FakeNotifier(rule: _rule());
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Confirmation dialog is open.
    expect(find.text('Delete Mod Rule'), findsOneWidget);

    // Confirm via the second (confirmation) dialog's Delete button.
    await tester.tap(find.descendant(
      of: find.byType(Dialog).last,
      matching: find.text('Delete'),
    ));
    await tester.pumpAndSettle();

    expect(fake.deleteCalls, 1);
    expect(find.text('Mod Translation Rule'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('cancelling the delete dialog deletes nothing', (tester) async {
    final fake = _FakeNotifier(rule: _rule());
    await pumpDialog(tester, fake);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(
      of: find.byType(Dialog).last,
      matching: find.text('Cancel'),
    ));
    await tester.pumpAndSettle();

    expect(fake.deleteCalls, 0);
    expect(find.text('Mod Translation Rule'), findsOneWidget); // still open
  });
}
