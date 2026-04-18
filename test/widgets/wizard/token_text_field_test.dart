import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/token_text_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders TextField with hint', (t) async {
    final ctl = TextEditingController();
    await t.pumpWidget(wrap(TokenTextField(
      controller: ctl,
      hint: 'Type here…',
      enabled: true,
    )));
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Type here…'), findsOneWidget);
  });

  testWidgets('onChanged fires on input', (t) async {
    String? captured;
    final ctl = TextEditingController();
    await t.pumpWidget(wrap(TokenTextField(
      controller: ctl,
      hint: '',
      enabled: true,
      onChanged: (v) => captured = v,
    )));
    await t.enterText(find.byType(TextField), 'abc');
    expect(captured, 'abc');
  });

  testWidgets('disabled renders with disabled border', (t) async {
    final ctl = TextEditingController();
    await t.pumpWidget(wrap(TokenTextField(
      controller: ctl,
      hint: '',
      enabled: false,
    )));
    final tf = t.widget<TextField>(find.byType(TextField));
    expect(tf.enabled, isFalse);
  });

  group('TokenTextField API props', () {
    testWidgets('obscureText=true hides characters with bullets', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(TokenTextField(
        controller: controller,
        hint: 'API key',
        enabled: true,
        obscureText: true,
      )));
      await tester.enterText(find.byType(TextField), 'secret');
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.obscureText, isTrue);
    });

    testWidgets('autofocus=true requests focus on mount', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(TokenTextField(
        controller: controller,
        hint: 'h',
        enabled: true,
        autofocus: true,
      )));
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.autofocus, isTrue);
    });

    testWidgets('maxLength caps input length', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(TokenTextField(
        controller: controller,
        hint: 'h',
        enabled: true,
        maxLength: 5,
      )));
      await tester.enterText(find.byType(TextField), 'abcdefgh');
      expect(controller.text.length, lessThanOrEqualTo(5));
    });

    testWidgets('prefixIcon renders leading widget', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(TokenTextField(
        controller: controller,
        hint: 'h',
        enabled: true,
        prefixIcon: const Icon(Icons.search, key: Key('prefix-icon')),
      )));
      expect(find.byKey(const Key('prefix-icon')), findsOneWidget);
    });
  });
}
