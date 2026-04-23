import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Padding(padding: const EdgeInsets.all(12), child: child)),
      );

  testWidgets('renders uppercase kicker + key/value lines', (t) async {
    await t.pumpWidget(wrap(const SummaryBox(
      label: 'Will generate',
      lines: [
        SummaryLine(key: 'Filename', value: 'foo.pack'),
        SummaryLine(key: 'Size', value: '3.2 MB'),
      ],
    )));
    expect(find.text('WILL GENERATE'), findsOneWidget);
    expect(find.text('Filename'), findsOneWidget);
    expect(find.text('foo.pack'), findsOneWidget);
    expect(find.text('Size'), findsOneWidget);
    expect(find.text('3.2 MB'), findsOneWidget);
  });

  testWidgets('semantics applies color to kicker', (t) async {
    await t.pumpWidget(wrap(const SummaryBox(
      label: 'X',
      semantics: SummarySemantics.warn,
      lines: [SummaryLine(key: 'K', value: 'V')],
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final kicker = t.widget<Text>(find.text('X'));
    expect(kicker.style?.color, tokens.warn);
  });

  testWidgets('per-line semantics overrides box semantics', (t) async {
    await t.pumpWidget(wrap(const SummaryBox(
      label: 'X',
      semantics: SummarySemantics.accent,
      lines: [
        SummaryLine(key: 'OK', value: '1', semantics: SummarySemantics.ok),
      ],
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    expect(t.widget<Text>(find.text('1')).style?.color, tokens.ok);
  });

  testWidgets('long value does not overflow in a narrow host', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.atelierDarkTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 303,
            child: const SummaryBox(
              label: 'Will generate',
              lines: [
                SummaryLine(
                  key: 'Filename',
                  value:
                      'very_long_pack_name_that_definitely_exceeds_available_width.pack',
                ),
              ],
            ),
          ),
        ),
      ),
    ));
    await t.pump();
    expect(t.takeException(), isNull,
        reason: 'SummaryBox must not overflow when the value is longer than '
            'the available width');
  });
}
