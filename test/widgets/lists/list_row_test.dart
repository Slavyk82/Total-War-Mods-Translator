import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/list_row.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('ListRow lays out children across columns', (t) async {
    await t.pumpWidget(wrap(
      ListRow(
        columns: const [ListRowColumn.fixed(80), ListRowColumn.flex(1), ListRowColumn.fixed(120)],
        children: const [Text('A'), Text('B'), Text('C')],
      ),
    ));
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('ListRow selected border-left uses accent', (t) async {
    await t.pumpWidget(wrap(
      ListRow(
        selected: true,
        columns: const [ListRowColumn.flex(1)],
        children: const [Text('row')],
      ),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.ancestor(of: find.text('row'), matching: find.byType(Container)).first,
    );
    final deco = container.decoration as BoxDecoration;
    expect((deco.border as Border).left.color, tokens.accent);
    expect((deco.border as Border).left.width, 2);
  });

  testWidgets('ListRow onTap fires', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(
      ListRow(
        columns: const [ListRowColumn.flex(1)],
        onTap: () => tapped = true,
        children: const [Text('row')],
      ),
    ));
    await t.tap(find.text('row'));
    expect(tapped, isTrue);
  });

  testWidgets('ListRow trailingAction renders', (t) async {
    await t.pumpWidget(wrap(
      ListRow(
        columns: const [ListRowColumn.flex(1)],
        trailingAction: const Icon(Icons.more_vert),
        children: const [Text('row')],
      ),
    ));
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('ListRowHeader renders labels in caps mono', (t) async {
    await t.pumpWidget(wrap(
      ListRowHeader(
        columns: const [ListRowColumn.fixed(80), ListRowColumn.flex(1)],
        labels: const ['NAME', 'DESCRIPTION'],
      ),
    ));
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('DESCRIPTION'), findsOneWidget);
  });
}
