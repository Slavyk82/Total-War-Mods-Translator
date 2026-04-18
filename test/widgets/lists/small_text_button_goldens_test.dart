// Golden tests for SmallTextButton filled variant across 2 themes (Plan 5f - T5).
//
// Pins the visual output of the newly-added `filled: true` variant after
// retokenisation via TwmtThemeTokens. Outlined goldens are not included here
// — only the new filled variant is covered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../helpers/test_helpers.dart';

void main() {
  Future<void> runSmallTextButtonFilledGolden(
    WidgetTester tester, {
    required ThemeData theme,
    required String goldenName,
  }) async {
    await tester.binding.setSurfaceSize(const Size(200, 80));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      Center(
        child: SmallTextButton(
          label: 'Restart Now',
          filled: true,
          onTap: () {},
        ),
      ),
      theme: theme,
      screenSize: const Size(200, 80),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(SmallTextButton),
      matchesGoldenFile('goldens/$goldenName.png'),
    );
  }

  testWidgets('small text button filled atelier', (tester) async {
    await runSmallTextButtonFilledGolden(
      tester,
      theme: AppTheme.atelierDarkTheme,
      goldenName: 'small_text_button_filled_atelier',
    );
  });

  testWidgets('small text button filled forge', (tester) async {
    await runSmallTextButtonFilledGolden(
      tester,
      theme: AppTheme.forgeDarkTheme,
      goldenName: 'small_text_button_filled_forge',
    );
  });
}
