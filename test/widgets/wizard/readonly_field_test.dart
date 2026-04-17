import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/readonly_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders label + value', (t) async {
    await t.pumpWidget(wrap(const ReadonlyField(
      label: 'Pack path',
      value: 'C:/data/foo.pack',
    )));
    expect(find.text('Pack path'), findsOneWidget);
    expect(find.text('C:/data/foo.pack'), findsOneWidget);
  });

  testWidgets('empty value renders em-dash', (t) async {
    await t.pumpWidget(wrap(const ReadonlyField(
      label: 'L',
      value: '',
    )));
    expect(find.text('—'), findsOneWidget);
  });
}
