// Golden tests for FluentToastWidget across 4 types x 2 themes (Plan 5f - T4).
//
// These pin the visual output of the unified FluentToast widget after
// retokenisation via TwmtThemeTokens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/fluent/fluent_toast.dart';

import '../../helpers/test_helpers.dart';

void main() {
  Future<void> runToastGolden(
    WidgetTester tester, {
    required ThemeData theme,
    required FluentToastType type,
    required String goldenName,
  }) async {
    await tester.binding.setSurfaceSize(const Size(600, 200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      Stack(
        children: [
          FluentToastWidget(
            message: 'Sample message',
            type: type,
            // 30m keeps the pending auto-dismiss out of the way; we drain it
            // at the end of the test before tear-down.
            duration: const Duration(minutes: 30),
            onDismissed: () {},
          ),
        ],
      ),
      theme: theme,
      screenSize: const Size(600, 200),
    ));
    // Allow the entry slide/fade to settle.
    await tester.pump(const Duration(milliseconds: 300));

    await expectLater(
      find.byType(FluentToastWidget),
      matchesGoldenFile('goldens/$goldenName.png'),
    );

    // Drain the pending auto-dismiss timer so no pending timers remain at
    // tear-down. `pumpAndSettle` completes the reverse animation.
    await tester.pump(const Duration(minutes: 31));
    await tester.pumpAndSettle();
  }

  for (final type in FluentToastType.values) {
    testWidgets('fluent toast atelier ${type.name}', (tester) async {
      await runToastGolden(
        tester,
        theme: AppTheme.atelierDarkTheme,
        type: type,
        goldenName: 'fluent_toast_atelier_${type.name}',
      );
    });

    testWidgets('fluent toast forge ${type.name}', (tester) async {
      await runToastGolden(
        tester,
        theme: AppTheme.forgeDarkTheme,
        type: type,
        goldenName: 'fluent_toast_forge_${type.name}',
      );
    });
  }
}
