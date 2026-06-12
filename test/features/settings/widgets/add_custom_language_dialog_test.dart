import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/settings/widgets/add_custom_language_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

typedef _LangRecord = ({String code, String name});

Future<List<_LangRecord?>> _open(WidgetTester tester) async {
  // Give the dialog a tall surface so its Column never overflows in tests.
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final results = <_LangRecord?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(extensions: [slateTokens]),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              results.add(await showDialog<_LangRecord>(
                context: context,
                builder: (_) => const AddCustomLanguageDialog(),
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

Future<void> _enterCode(WidgetTester tester, String code) =>
    tester.enterText(find.byType(TextField).at(0), code);

Future<void> _enterName(WidgetTester tester, String name) =>
    tester.enterText(find.byType(TextField).at(1), name);

Future<void> _tapAdd(WidgetTester tester) async {
  await tester.tap(find.text(t.settings.addCustomLanguage.add));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the add-language title and two fields', (tester) async {
    await _open(tester);

    expect(find.text(t.settings.addCustomLanguage.title), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('empty submission reports both required fields', (tester) async {
    final results = await _open(tester);

    await _tapAdd(tester);

    expect(find.text(t.settings.addCustomLanguage.errors.codeRequired),
        findsOneWidget);
    expect(find.text(t.settings.addCustomLanguage.errors.nameRequired),
        findsOneWidget);
    expect(results, isEmpty);
  });

  testWidgets('a one-letter code is rejected as too short', (tester) async {
    await _open(tester);

    await _enterCode(tester, 'a');
    await _enterName(tester, 'Custom');
    await _tapAdd(tester);

    expect(find.text(t.settings.addCustomLanguage.errors.codeTooShort),
        findsOneWidget);
  });

  testWidgets('a code with digits is rejected as letters-only', (tester) async {
    await _open(tester);

    await _enterCode(tester, 'a1');
    await _enterName(tester, 'Custom');
    await _tapAdd(tester);

    expect(find.text(t.settings.addCustomLanguage.errors.codeLettersOnly),
        findsOneWidget);
  });

  testWidgets('a valid code and name pop the trimmed record', (tester) async {
    final results = await _open(tester);

    await _enterCode(tester, '  zz  ');
    await _enterName(tester, '  Custom Lang  ');
    await _tapAdd(tester);

    expect(results.single, (code: 'zz', name: 'Custom Lang'));
  });
}
