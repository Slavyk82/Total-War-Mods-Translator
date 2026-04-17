import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/form_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders uppercase label + children', (t) async {
    await t.pumpWidget(wrap(const FormSection(
      label: 'Basics',
      children: [Text('f1'), Text('f2')],
    )));
    expect(find.text('BASICS'), findsOneWidget);
    expect(find.text('f1'), findsOneWidget);
    expect(find.text('f2'), findsOneWidget);
  });

  testWidgets('renders helpText when provided', (t) async {
    await t.pumpWidget(wrap(const FormSection(
      label: 'L',
      helpText: 'Help me',
      children: [Text('c')],
    )));
    expect(find.text('Help me'), findsOneWidget);
  });

  testWidgets('omits helpText when null', (t) async {
    await t.pumpWidget(wrap(const FormSection(
      label: 'L',
      children: [Text('c')],
    )));
    expect(find.byKey(const Key('form-section-help-text')), findsNothing);
  });
}
