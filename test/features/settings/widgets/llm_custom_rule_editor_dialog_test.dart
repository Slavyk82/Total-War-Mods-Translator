import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/llm_custom_rule_editor_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/llm_custom_rule.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

LlmCustomRule _rule(String text) => LlmCustomRule(
      id: 'id-1',
      ruleText: text,
      isEnabled: true,
      createdAt: 0,
      updatedAt: 0,
    );

Future<List<String?>> _open(WidgetTester tester, {LlmCustomRule? existing}) async {
  // The dialog hosts a 10-14 line text field; give it a tall surface so the
  // Column does not overflow (which would throw) and the actions stay tappable.
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final results = <String?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(extensions: [slateTokens]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await showDialog<String>(
                context: context,
                builder: (_) => LlmCustomRuleEditorDialog(existingRule: existing),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('add mode shows the add title', (tester) async {
    await _open(tester);

    expect(find.text(t.settings.customRules.editorDialog.addTitle),
        findsOneWidget);
  });

  testWidgets('edit mode pre-fills the existing rule text', (tester) async {
    await _open(tester, existing: _rule('keep names untranslated'));

    expect(find.text(t.settings.customRules.editorDialog.editTitle),
        findsOneWidget);
    expect(find.text('keep names untranslated'), findsOneWidget);
  });

  testWidgets('empty submission shows a validation error and does not pop',
      (tester) async {
    final results = await _open(tester);

    await tester.tap(find.text(t.settings.customRules.editorDialog.add));
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.customRules.editorDialog.errors.ruleTextRequired),
      findsOneWidget,
    );
    expect(results, isEmpty);
  });

  testWidgets('a trimmed non-empty rule is popped', (tester) async {
    final results = await _open(tester);

    await tester.enterText(find.byType(TextField), '  do not translate IDs  ');
    await tester.tap(find.text(t.settings.customRules.editorDialog.add));
    await tester.pumpAndSettle();

    expect(results.single, 'do not translate IDs');
  });
}
