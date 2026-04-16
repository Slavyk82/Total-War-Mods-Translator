import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/home/providers/home_status_provider.dart';
import 'package:twmt/features/home/widgets/home_page_header.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  // The widget reads `context.tokens`, which requires the TWMT theme
  // extension to be installed on `ThemeData`. Use the atelier theme for
  // every test below.
  Widget wrap(Widget child) => createThemedTestableWidget(
        child,
        theme: AppTheme.atelierDarkTheme,
        overrides: [
          homeStatusProvider.overrideWith(
            (ref) async => const HomeStatus(HomeStatusKind.allCaughtUp, 0),
          ),
        ],
      );

  testWidgets('renders "Home" title', (tester) async {
    await tester.pumpWidget(wrap(const HomePageHeader()));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('sub-line shows "All caught up" when status = allCaughtUp',
      (tester) async {
    await tester.pumpWidget(wrap(const HomePageHeader()));
    await tester.pumpAndSettle();

    expect(find.text('All caught up'), findsOneWidget);
  });

  testWidgets('renders Command and New project button labels', (tester) async {
    await tester.pumpWidget(wrap(const HomePageHeader()));
    await tester.pumpAndSettle();

    // The command button label is "Command  ⌘K"; match on the "Command"
    // prefix via a widget predicate to stay resilient to spacing changes.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('Command') ?? false),
      ),
      findsOneWidget,
    );
    expect(find.text('+ New project'), findsOneWidget);
  });

  testWidgets('Command button is disabled (onPressed == null)',
      (tester) async {
    await tester.pumpWidget(wrap(const HomePageHeader()));
    await tester.pumpAndSettle();

    final btn = tester.widget<TextButton>(
      find.byKey(const Key('HomePageHeader.CommandButton')),
    );
    expect(btn.onPressed, isNull);
  });
}
