import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/right_sticky_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: Row(children: [const Expanded(child: SizedBox()), child]),
          ),
        ),
      );

  testWidgets('panel width defaults to 380', (t) async {
    await t.pumpWidget(wrap(const RightStickyPanel(children: [Text('c')])));
    final sized = t.widget<SizedBox>(find.ancestor(
      of: find.text('c'),
      matching: find.byType(SizedBox),
    ).first);
    expect(sized.width, 380);
  });

  testWidgets('respects custom width', (t) async {
    await t.pumpWidget(wrap(const RightStickyPanel(
      width: 320,
      children: [Text('c')],
    )));
    final sized = t.widget<SizedBox>(find.ancestor(
      of: find.text('c'),
      matching: find.byType(SizedBox),
    ).first);
    expect(sized.width, 320);
  });

  testWidgets('renders children in order', (t) async {
    await t.pumpWidget(wrap(const RightStickyPanel(children: [
      Text('first'),
      Text('second'),
    ])));
    final firstRect = t.getRect(find.text('first'));
    final secondRect = t.getRect(find.text('second'));
    expect(firstRect.top, lessThan(secondRect.top));
  });
}
