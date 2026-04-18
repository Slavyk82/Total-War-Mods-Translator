import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/settings/settings_accordion_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      );

  testWidgets('renders header collapsed by default', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'My section',
      subtitle: 'Some description',
      child: Text('expanded-content'),
    )));
    expect(find.text('My section'), findsOneWidget);
    expect(find.text('Some description'), findsOneWidget);
    expect(find.text('expanded-content'), findsNothing);
  });

  testWidgets('tapping header expands and shows child', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'Title',
      subtitle: 'Sub',
      child: Text('expanded-content'),
    )));
    await t.tap(find.text('Title'));
    await t.pumpAndSettle();
    expect(find.text('expanded-content'), findsOneWidget);
  });

  testWidgets('shows StatusPill when activeCount > 0', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'T',
      subtitle: 'S',
      activeCount: 3,
      child: SizedBox.shrink(),
    )));
    expect(find.text('3 active'), findsOneWidget);
  });

  testWidgets('hides StatusPill when activeCount is null or 0', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'T',
      subtitle: 'S',
      activeCount: 0,
      child: SizedBox.shrink(),
    )));
    expect(find.textContaining('active'), findsNothing);
  });

  testWidgets('initiallyExpanded=true renders child on first frame', (t) async {
    await t.pumpWidget(wrap(const SettingsAccordionSection(
      icon: FluentIcons.add_24_regular,
      title: 'T',
      subtitle: 'S',
      initiallyExpanded: true,
      child: Text('up-front'),
    )));
    expect(find.text('up-front'), findsOneWidget);
  });
}
