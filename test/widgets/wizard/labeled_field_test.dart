import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/labeled_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders label + child', (t) async {
    await t.pumpWidget(wrap(const LabeledField(
      label: 'Title',
      child: Text('field-widget'),
    )));
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('field-widget'), findsOneWidget);
  });

  testWidgets('label uses fontBody 11 textDim w500', (t) async {
    await t.pumpWidget(wrap(const LabeledField(
      label: 'T',
      child: SizedBox.shrink(),
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('T'));
    expect(text.style?.fontSize, 11);
    expect(text.style?.color, tokens.textDim);
    expect(text.style?.fontWeight, FontWeight.w500);
  });

  testWidgets('renders without a label crash when child is empty', (t) async {
    await t.pumpWidget(wrap(const LabeledField(
      label: 'X',
      child: SizedBox.shrink(),
    )));
    expect(find.text('X'), findsOneWidget);
  });
}
