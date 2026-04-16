import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('FilterPill off state uses panel2 bg + textMid fg', (t) async {
    await t.pumpWidget(wrap(FilterPill(label: 'ALL', selected: false, onToggle: () {})));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(FilterPill),
        matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.panel2);
  });

  testWidgets('FilterPill on state uses accentBg + accent border', (t) async {
    await t.pumpWidget(wrap(FilterPill(label: 'ALL', selected: true, onToggle: () {})));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(FilterPill),
        matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.accentBg);
    expect((deco.border as Border).top.color, tokens.accent);
  });

  testWidgets('FilterPill shows count in mono', (t) async {
    await t.pumpWidget(wrap(FilterPill(label: 'ALL', selected: false, count: 42, onToggle: () {})));
    expect(find.text('42'), findsOneWidget);
  });

  testWidgets('FilterPill onToggle fires', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(FilterPill(label: 'X', selected: false, onToggle: () => tapped = true)));
    await t.tap(find.byType(FilterPill));
    expect(tapped, isTrue);
  });

  testWidgets('FilterPillGroup renders label + children', (t) async {
    await t.pumpWidget(wrap(
      FilterPillGroup(
        label: 'ÉTAT',
        pills: [
          FilterPill(label: 'A', selected: false, onToggle: () {}),
          FilterPill(label: 'B', selected: true, onToggle: () {}),
        ],
      ),
    ));
    expect(find.text('ÉTAT'), findsOneWidget);
    expect(find.byType(FilterPill), findsNWidgets(2));
  });

  testWidgets('FilterPill renders Tooltip with message when tooltip is set', (t) async {
    await t.pumpWidget(wrap(FilterPill(
      label: 'X',
      selected: false,
      onToggle: () {},
      tooltip: 'Filter description',
    )));
    expect(
      find.descendant(
        of: find.byType(FilterPill),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Filter description',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('FilterPill has no Tooltip ancestor when tooltip is null', (t) async {
    await t.pumpWidget(wrap(FilterPill(
      label: 'X',
      selected: false,
      onToggle: () {},
    )));
    expect(
      find.descendant(
        of: find.byType(FilterPill),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });

  testWidgets('FilterPillGroup renders clear terminator when a pill is selected', (t) async {
    var cleared = false;
    await t.pumpWidget(wrap(
      FilterPillGroup(
        label: 'STATE',
        onClear: () => cleared = true,
        clearLabel: 'Clear',
        pills: [
          FilterPill(label: 'A', selected: true, onToggle: () {}),
          FilterPill(label: 'B', selected: false, onToggle: () {}),
        ],
      ),
    ));
    expect(find.text('Clear'), findsOneWidget);
    await t.tap(find.text('Clear'));
    expect(cleared, isTrue);
  });

  testWidgets('FilterPillGroup hides clear terminator when no pill is selected', (t) async {
    await t.pumpWidget(wrap(
      FilterPillGroup(
        label: 'STATE',
        onClear: () {},
        pills: [
          FilterPill(label: 'A', selected: false, onToggle: () {}),
          FilterPill(label: 'B', selected: false, onToggle: () {}),
        ],
      ),
    ));
    expect(find.text('Clear'), findsNothing);
  });
}
