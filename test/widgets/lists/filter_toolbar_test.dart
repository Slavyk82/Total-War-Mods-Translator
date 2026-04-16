import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('FilterToolbar renders leading + trailing on row 1', (t) async {
    await t.pumpWidget(wrap(const FilterToolbar(leading: Text('Projects'), trailing: [Icon(Icons.search)])));
    expect(find.text('Projects'), findsOneWidget);
    expect(find.byIcon(Icons.search), findsOneWidget);
  });

  testWidgets('FilterToolbar hides pill row when pillGroups empty', (t) async {
    await t.pumpWidget(wrap(const FilterToolbar(leading: Text('X'), pillGroups: [])));
    expect(find.byType(FilterPillGroup), findsNothing);
  });

  testWidgets('FilterToolbar shows pillGroups on row 2', (t) async {
    await t.pumpWidget(wrap(
      FilterToolbar(
        leading: const Text('X'),
        pillGroups: [
          FilterPillGroup(
            label: 'STATE',
            pills: [FilterPill(label: 'A', selected: false, onToggle: () {})],
          ),
        ],
      ),
    ));
    expect(find.text('STATE'), findsOneWidget);
    expect(find.byType(FilterPill), findsOneWidget);
  });
}
