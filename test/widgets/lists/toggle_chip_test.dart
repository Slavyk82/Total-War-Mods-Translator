import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/toggle_chip.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('ToggleChip off state uses panel2 bg + border', (t) async {
    await t.pumpWidget(wrap(ToggleChip(
      label: 'Hidden',
      selected: false,
      onToggle: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(ToggleChip),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.panel2);
    expect((deco.border as Border).top.color, tokens.border);
  });

  testWidgets('ToggleChip on state uses accentBg + accent border', (t) async {
    await t.pumpWidget(wrap(ToggleChip(
      label: 'Hidden',
      selected: true,
      onToggle: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(ToggleChip),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.accentBg);
    expect((deco.border as Border).top.color, tokens.accent);
  });

  testWidgets('ToggleChip renders count when provided', (t) async {
    await t.pumpWidget(wrap(ToggleChip(
      label: 'Hidden',
      selected: false,
      count: 7,
      onToggle: () {},
    )));
    expect(find.text('7'), findsOneWidget);
  });

  testWidgets('ToggleChip renders icon when provided', (t) async {
    await t.pumpWidget(wrap(ToggleChip(
      label: 'Hidden',
      selected: false,
      icon: Icons.visibility_off,
      onToggle: () {},
    )));
    expect(find.byIcon(Icons.visibility_off), findsOneWidget);
  });

  testWidgets('ToggleChip fires onToggle on tap', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(ToggleChip(
      label: 'Hidden',
      selected: false,
      onToggle: () => tapped = true,
    )));
    await t.tap(find.byType(ToggleChip));
    expect(tapped, isTrue);
  });

  testWidgets('ToggleChip wraps in Tooltip when tooltip is set', (t) async {
    await t.pumpWidget(wrap(ToggleChip(
      label: 'Hidden',
      selected: false,
      tooltip: 'Show hidden mods',
      onToggle: () {},
    )));
    expect(
      find.descendant(
        of: find.byType(ToggleChip),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Show hidden mods',
        ),
      ),
      findsOneWidget,
    );
  });
}
