import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/cards/workflow_card.dart';
import '../../helpers/test_bootstrap.dart';
import '../../helpers/test_helpers.dart';

void main() {
  setUp(() async => TestBootstrap.registerFakes());

  testWidgets('renders number, title, state, metric, sub, cta', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowCard(
        stepNumber: 2,
        title: 'Translate',
        stateLabel: 'In progress',
        metric: '24',
        subtitle: '24 active projects',
        cta: 'Open projects',
        state: WorkflowCardState.current,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Translate'), findsOneWidget);
    // State label is rendered uppercase.
    expect(find.text('IN PROGRESS'), findsOneWidget);
    expect(find.text('24'), findsOneWidget);
    expect(find.text('24 active projects'), findsOneWidget);
    expect(find.text('Open projects'), findsOneWidget);
  });

  testWidgets('done state shows check mark instead of number', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowCard(
        stepNumber: 1,
        title: 'Detect',
        stateLabel: 'Done',
        metric: '187',
        subtitle: '',
        cta: 'View mods',
        state: WorkflowCardState.done,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    expect(find.text('1'), findsNothing);
    expect(find.text('✓'), findsOneWidget);
  });

  testWidgets('next state hides the CTA row', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const WorkflowCard(
        stepNumber: 3,
        title: 'Compile',
        stateLabel: '3 ready',
        metric: '3',
        subtitle: '',
        cta: 'Compile',
        state: WorkflowCardState.next,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    // Title is still rendered; CTA text "Compile" would duplicate it, so we
    // scope the absence check to the CTA row's key.
    expect(find.text('Compile'), findsOneWidget);
    expect(find.byKey(const Key('WorkflowCardCTA')), findsNothing);
  });

  testWidgets('onTap invoked', (tester) async {
    var taps = 0;
    await tester.pumpWidget(createThemedTestableWidget(
      WorkflowCard(
        stepNumber: 2,
        title: 'Translate',
        stateLabel: 'In progress',
        metric: '24',
        subtitle: '',
        cta: 'Open projects',
        state: WorkflowCardState.current,
        onTap: () => taps++,
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.tap(find.byType(WorkflowCard));
    expect(taps, 1);
  });
}
