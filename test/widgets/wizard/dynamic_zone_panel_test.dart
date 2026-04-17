import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders child', (t) async {
    await t.pumpWidget(wrap(const DynamicZonePanel(child: Text('dyn'))));
    expect(find.text('dyn'), findsOneWidget);
  });

  testWidgets('applies custom padding', (t) async {
    await t.pumpWidget(wrap(const DynamicZonePanel(
      padding: EdgeInsets.all(8),
      child: Text('p'),
    )));
    final padding = t.widget<Padding>(find.ancestor(
      of: find.text('p'),
      matching: find.byType(Padding),
    ).first);
    expect(padding.padding, const EdgeInsets.all(8));
  });
}
