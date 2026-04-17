import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/settings/settings_tab_bar.dart';

void main() {
  Widget wrap(Widget child, {ThemeData? theme}) => MaterialApp(
        theme: theme ?? AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: DefaultTabController(
            length: 2,
            child: Column(
              children: [child, const Expanded(child: SizedBox())],
            ),
          ),
        ),
      );

  testWidgets('renders one tab per item with label + icon', (t) async {
    await t.pumpWidget(wrap(const SettingsTabBar(tabs: [
      SettingsTabItem(icon: FluentIcons.settings_24_regular, label: 'General'),
      SettingsTabItem(icon: FluentIcons.folder_24_regular, label: 'Folders'),
    ])));
    expect(find.text('General'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
    expect(find.byIcon(FluentIcons.settings_24_regular), findsOneWidget);
    expect(find.byIcon(FluentIcons.folder_24_regular), findsOneWidget);
  });

  testWidgets('TabBar labelColor = tokens.text, unselectedLabelColor = tokens.textDim', (t) async {
    await t.pumpWidget(wrap(const SettingsTabBar(tabs: [
      SettingsTabItem(icon: FluentIcons.settings_24_regular, label: 'General'),
      SettingsTabItem(icon: FluentIcons.folder_24_regular, label: 'Folders'),
    ])));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final bar = t.widget<TabBar>(find.byType(TabBar));
    expect(bar.labelColor, equals(tokens.text));
    expect(bar.unselectedLabelColor, equals(tokens.textDim));
  });

  testWidgets('tab bar is horizontally scrollable', (t) async {
    await t.pumpWidget(wrap(const SettingsTabBar(tabs: [
      SettingsTabItem(icon: FluentIcons.settings_24_regular, label: 'General'),
      SettingsTabItem(icon: FluentIcons.folder_24_regular, label: 'Folders'),
    ])));
    final bar = t.widget<TabBar>(find.byType(TabBar));
    expect(bar.isScrollable, isTrue);
  });
}
