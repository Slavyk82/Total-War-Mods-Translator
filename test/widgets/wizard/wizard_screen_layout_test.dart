import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/dynamic_zone_panel.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: SizedBox(width: 1600, height: 900, child: child)),
      );

  testWidgets('composes toolbar, form, and dynamic zone', (t) async {
    await t.pumpWidget(wrap(const WizardScreenLayout(
      toolbar: Text('TBAR'),
      formPanel: StickyFormPanel(
        sections: [FormSection(label: 'X', children: [Text('field')])],
      ),
      dynamicZone: DynamicZonePanel(child: Text('DYN')),
    )));
    expect(find.text('TBAR'), findsOneWidget);
    expect(find.text('field'), findsOneWidget);
    expect(find.text('DYN'), findsOneWidget);
  });

  testWidgets('form panel left of dynamic zone', (t) async {
    await t.pumpWidget(wrap(const WizardScreenLayout(
      toolbar: Text('t'),
      formPanel: StickyFormPanel(
        sections: [FormSection(label: 'S', children: [Text('left')])],
      ),
      dynamicZone: DynamicZonePanel(child: Text('right')),
    )));
    final leftRect = t.getRect(find.text('left'));
    final rightRect = t.getRect(find.text('right'));
    expect(leftRect.left, lessThan(rightRect.left));
  });
}
