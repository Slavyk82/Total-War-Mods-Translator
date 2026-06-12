import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/ignored_source_text_editor_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

IgnoredSourceText _existing(String text) => IgnoredSourceText(
      id: 'id-1',
      sourceText: text,
      createdAt: 0,
      updatedAt: 0,
    );

/// Opens the editor dialog and records its String pop result.
Future<List<String?>> _open(
  WidgetTester tester, {
  IgnoredSourceText? existing,
}) async {
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
                builder: (_) =>
                    IgnoredSourceTextEditorDialog(existingText: existing),
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
  testWidgets('add mode shows the add title and an empty field',
      (tester) async {
    await _open(tester);

    expect(find.text(t.settings.ignoredTexts.editorDialog.addTitle),
        findsOneWidget);
  });

  testWidgets('edit mode pre-fills the existing source text', (tester) async {
    await _open(tester, existing: _existing('hello world'));

    expect(find.text(t.settings.ignoredTexts.editorDialog.editTitle),
        findsOneWidget);
    expect(find.text('hello world'), findsOneWidget);
  });

  testWidgets('saving an empty value shows a validation error and does not pop',
      (tester) async {
    final results = await _open(tester);

    await tester.tap(find.text(t.settings.ignoredTexts.editorDialog.add));
    await tester.pumpAndSettle();

    expect(
      find.text(t.settings.ignoredTexts.editorDialog.errors.sourceTextRequired),
      findsOneWidget,
    );
    expect(results, isEmpty); // dialog stayed open
  });

  testWidgets('saving a trimmed non-empty value pops it', (tester) async {
    final results = await _open(tester);

    await tester.enterText(find.byType(TextField), '  needle  ');
    await tester.tap(find.text(t.settings.ignoredTexts.editorDialog.add));
    await tester.pumpAndSettle();

    expect(results.single, 'needle');
  });
}
