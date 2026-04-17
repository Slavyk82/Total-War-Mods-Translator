import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/language_selection_tile.dart';

void main() {
  const french = Language(
    id: 'lang-fr',
    code: 'fr',
    name: 'French',
    nativeName: 'Français',
    isActive: true,
    isCustom: false,
  );

  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(
          body: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      );

  testWidgets('renders language display name', (t) async {
    await t.pumpWidget(wrap(LanguageSelectionTile(
      language: french,
      isSelected: false,
      onTap: () {},
    )));
    expect(find.text('French (Français)'), findsOneWidget);
  });

  testWidgets('onTap fires when tapped', (t) async {
    var taps = 0;
    await t.pumpWidget(wrap(LanguageSelectionTile(
      language: french,
      isSelected: false,
      onTap: () => taps++,
    )));
    await t.tap(find.text('French (Français)'));
    expect(taps, 1);
  });

  testWidgets('shows checkmark when selected', (t) async {
    await t.pumpWidget(wrap(LanguageSelectionTile(
      language: french,
      isSelected: true,
      onTap: () {},
    )));
    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsOneWidget);
  });

  testWidgets('omits checkmark when not selected', (t) async {
    await t.pumpWidget(wrap(LanguageSelectionTile(
      language: french,
      isSelected: false,
      onTap: () {},
    )));
    expect(find.byIcon(FluentIcons.checkmark_24_regular), findsNothing);
  });
}
