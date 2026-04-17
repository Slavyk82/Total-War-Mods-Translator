import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/form_section.dart';
import 'package:twmt/widgets/wizard/sticky_form_panel.dart';
import 'package:twmt/widgets/wizard/summary_box.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: SizedBox(width: 1200, height: 800, child: Row(children: [child, const Expanded(child: SizedBox())]))),
      );

  testWidgets('panel width defaults to 380', (t) async {
    await t.pumpWidget(wrap(const StickyFormPanel(
      sections: [FormSection(label: 'X', children: [Text('c')])],
    )));
    final sized = t.widget<SizedBox>(find.ancestor(
      of: find.byType(FormSection),
      matching: find.byType(SizedBox),
    ).first);
    expect(sized.width, 380);
  });

  testWidgets('renders sections, summary, and actions', (t) async {
    await t.pumpWidget(wrap(StickyFormPanel(
      sections: const [FormSection(label: 'S', children: [Text('field')])],
      summary: const SummaryBox(label: 'sum', lines: [SummaryLine(key: 'k', value: 'v')]),
      actions: [const Text('Action-1')],
    )));
    expect(find.text('field'), findsOneWidget);
    expect(find.text('SUM'), findsOneWidget);
    expect(find.text('Action-1'), findsOneWidget);
  });

  testWidgets('omits summary when null', (t) async {
    await t.pumpWidget(wrap(const StickyFormPanel(
      sections: [FormSection(label: 'S', children: [Text('c')])],
    )));
    expect(find.byType(SummaryBox), findsNothing);
  });
}
