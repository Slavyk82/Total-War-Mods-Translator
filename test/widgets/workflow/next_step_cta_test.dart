import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/workflow/next_step_cta.dart';

void main() {
  testWidgets('renders "Next: <label>" text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(
          body: Center(
            child: NextStepCta(label: 'Compile this pack', onTap: null),
          ),
        ),
      ),
    );
    expect(find.text('Next: Compile this pack'), findsOneWidget);
  });

  testWidgets('invokes onTap when enabled', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: Center(
            child: NextStepCta(
              label: 'Compile',
              onTap: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(NextStepCta));
    expect(tapped, isTrue);
  });

  testWidgets('is non-tappable when onTap is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(
          body: Center(
            child: NextStepCta(label: 'Compile', onTap: null),
          ),
        ),
      ),
    );
    final gesture = tester.widget<GestureDetector>(
      find.descendant(
        of: find.byType(NextStepCta),
        matching: find.byType(GestureDetector),
      ),
    );
    expect(gesture.onTap, isNull);
  });

  testWidgets('defaults to arrow_right icon when none provided',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: const Scaffold(
          body: Center(
            child: NextStepCta(label: 'Compile', onTap: null),
          ),
        ),
      ),
    );
    expect(find.byIcon(FluentIcons.arrow_right_24_regular), findsOneWidget);
  });
}
