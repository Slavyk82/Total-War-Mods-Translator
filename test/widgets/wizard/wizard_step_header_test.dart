import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/wizard_step_header.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      );

  testWidgets('renders step counter + title', (t) async {
    await t.pumpWidget(wrap(const WizardStepHeader(
      stepNumber: 2,
      totalSteps: 3,
      title: 'Select something',
    )));
    expect(find.text('STEP 2/3'), findsOneWidget);
    expect(find.text('Select something'), findsOneWidget);
  });

  testWidgets('renders with step 1/2 format', (t) async {
    await t.pumpWidget(wrap(const WizardStepHeader(
      stepNumber: 1,
      totalSteps: 2,
      title: 'First',
    )));
    expect(find.text('STEP 1/2'), findsOneWidget);
  });
}
