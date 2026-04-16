import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/cards/action_card.dart';
import '../../helpers/test_bootstrap.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('renders label, value, desc', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ActionCard(
        label: 'To review',
        value: 2,
        description: 'projects with needs-review units',
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    expect(find.text('TO REVIEW'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('projects with needs-review units'), findsOneWidget);
  });

  testWidgets('shows pulsed dot when highlight=true and value>0',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ActionCard(
        label: 'Ready to compile',
        value: 3,
        description: '',
        highlight: true,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    expect(find.byKey(const Key('ActionCardPulseDot')), findsOneWidget);
  });

  testWidgets('no pulsed dot when value=0 even if highlight requested',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const ActionCard(
        label: 'To review',
        value: 0,
        description: '',
        highlight: true,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    expect(find.byKey(const Key('ActionCardPulseDot')), findsNothing);
  });

  testWidgets('onTap invoked on tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(createThemedTestableWidget(
      ActionCard(
        label: 'x',
        value: 1,
        description: 'y',
        onTap: () => tapped = true,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.tap(find.byType(ActionCard));
    expect(tapped, isTrue);
  });
}
