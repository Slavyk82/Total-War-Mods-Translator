import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('SmallTextButton renders the label', (t) async {
    await t.pumpWidget(wrap(SmallTextButton(label: 'All', onTap: () {})));
    expect(find.text('All'), findsOneWidget);
  });

  testWidgets('SmallTextButton uses panel2 bg + border tokens', (t) async {
    await t.pumpWidget(wrap(SmallTextButton(label: 'All', onTap: () {})));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(SmallTextButton),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.panel2);
    expect((deco.border as Border).top.color, tokens.border);
  });

  testWidgets('SmallTextButton fires onTap', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(SmallTextButton(
      label: 'Cancel',
      onTap: () => tapped = true,
    )));
    await t.tap(find.byType(SmallTextButton));
    expect(tapped, isTrue);
  });

  testWidgets('SmallTextButton wraps in Tooltip when tooltip is set', (t) async {
    await t.pumpWidget(wrap(SmallTextButton(
      label: 'All',
      tooltip: 'Select all items',
      onTap: () {},
    )));
    expect(
      find.descendant(
        of: find.byType(SmallTextButton),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Select all items',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SmallTextButton renders icon when provided', (t) async {
    await t.pumpWidget(wrap(SmallTextButton(
      label: 'X',
      icon: Icons.close,
      onTap: () {},
    )));
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('SmallTextButton filled=true uses accent bg + accentFg label',
      (t) async {
    await t.pumpWidget(wrap(SmallTextButton(
      label: 'Go',
      filled: true,
      onTap: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(SmallTextButton),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    // Filled variant routes bg through tokens.accent and border through
    // tokens.accent (not tokens.panel2 / tokens.border as in the outlined
    // default).
    expect(deco.color, tokens.accent);
    expect(deco.color, isNot(tokens.panel2));
    expect((deco.border as Border).top.color, tokens.accent);
    // Label text colour is tokens.accentFg (not tokens.textMid).
    final text = t.widget<Text>(find.text('Go'));
    expect(text.style?.color, tokens.accentFg);
    expect(text.style?.color, isNot(tokens.textMid));
  });

  testWidgets('SmallTextButton filled=true with icon tints icon with accentFg',
      (t) async {
    await t.pumpWidget(wrap(SmallTextButton(
      label: 'Go',
      icon: Icons.play_arrow,
      filled: true,
      onTap: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final icon = t.widget<Icon>(find.byIcon(Icons.play_arrow));
    expect(icon.color, tokens.accentFg);
  });
}
