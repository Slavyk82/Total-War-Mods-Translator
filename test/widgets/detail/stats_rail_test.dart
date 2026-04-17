import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/stats_rail.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders section label and rows', (t) async {
    await t.pumpWidget(wrap(
      const StatsRail(
        sections: [
          StatsRailSection(label: 'Overview', rows: [
            StatsRailRow(label: 'Translated', value: '84'),
            StatsRailRow(label: 'Pending', value: '40'),
          ]),
        ],
      ),
    ));
    expect(find.text('OVERVIEW'), findsOneWidget);
    expect(find.text('Translated'), findsOneWidget);
    expect(find.text('84'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
  });

  testWidgets('applies semantics colour to row value', (t) async {
    await t.pumpWidget(wrap(
      const StatsRail(
        sections: [
          StatsRailSection(label: 'S', rows: [
            StatsRailRow(
                label: 'OK', value: '1', semantics: StatsSemantics.ok),
            StatsRailRow(
                label: 'WARN', value: '2', semantics: StatsSemantics.warn),
            StatsRailRow(
                label: 'ERR', value: '3', semantics: StatsSemantics.err),
          ]),
        ],
      ),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    expect(t.widget<Text>(find.text('1')).style?.color, tokens.ok);
    expect(t.widget<Text>(find.text('2')).style?.color, tokens.warn);
    expect(t.widget<Text>(find.text('3')).style?.color, tokens.err);
  });

  testWidgets('renders optional header', (t) async {
    await t.pumpWidget(wrap(
      const StatsRail(
        header: Text('HEAD'),
        sections: [
          StatsRailSection(label: 'S', rows: [StatsRailRow(label: 'L', value: 'V')]),
        ],
      ),
    ));
    expect(find.text('HEAD'), findsOneWidget);
  });

  testWidgets('renders hint with kicker/message and fires onTap', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(
      StatsRail(
        sections: const [
          StatsRailSection(label: 'S', rows: [StatsRailRow(label: 'L', value: 'V')]),
        ],
        hint: StatsRailHint(
          kicker: 'NEXT',
          message: 'Review 2 units',
          semantics: StatsSemantics.err,
          onTap: () => tapped = true,
        ),
      ),
    ));
    expect(find.text('NEXT'), findsOneWidget);
    expect(find.text('Review 2 units'), findsOneWidget);
    await t.tap(find.text('Review 2 units'));
    expect(tapped, isTrue);
  });
}
