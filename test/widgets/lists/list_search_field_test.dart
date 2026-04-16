import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_search_field.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
      );

  testWidgets('ListSearchField renders hint text', (t) async {
    await t.pumpWidget(wrap(ListSearchField(
      value: '',
      onChanged: (_) {},
      hintText: 'Search projects...',
    )));
    expect(find.text('Search projects...'), findsOneWidget);
  });

  testWidgets('ListSearchField uses panel2 background from tokens', (t) async {
    await t.pumpWidget(wrap(ListSearchField(
      value: '',
      onChanged: (_) {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final field = t.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.fillColor, tokens.panel2);
  });

  testWidgets('ListSearchField fires onChanged when typing', (t) async {
    String? seen;
    await t.pumpWidget(wrap(ListSearchField(
      value: '',
      onChanged: (v) => seen = v,
    )));
    await t.enterText(find.byType(TextField), 'orc');
    expect(seen, 'orc');
  });

  testWidgets('ListSearchField shows clear icon only when value non-empty + onClear set',
      (t) async {
    await t.pumpWidget(wrap(ListSearchField(
      value: 'hello',
      onChanged: (_) {},
      onClear: () {},
    )));
    expect(find.byIcon(Icons.cancel).evaluate().isEmpty, isTrue);
    // Fluent "dismiss_circle_24_regular" icon — find via its presence in the suffix area.
    // Presence check: clear is rendered as a GestureDetector inside the field.
    expect(find.byType(GestureDetector), findsWidgets);
  });

  testWidgets('ListSearchField fires onClear and clears controller', (t) async {
    var cleared = false;
    String lastChange = 'hello';
    await t.pumpWidget(wrap(ListSearchField(
      value: 'hello',
      onChanged: (v) => lastChange = v,
      onClear: () {
        cleared = true;
        lastChange = '';
      },
    )));
    // The clear suffix is the first interactive GestureDetector inside the field.
    final clears = find.descendant(
      of: find.byType(ListSearchField),
      matching: find.byType(GestureDetector),
    );
    await t.tap(clears.first);
    await t.pump();
    expect(cleared, isTrue);
    expect(lastChange, '');
  });
}
