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
}
