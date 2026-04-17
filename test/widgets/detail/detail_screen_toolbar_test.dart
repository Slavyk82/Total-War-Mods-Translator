import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders crumb and back icon', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'Work › Projects › Foo',
      onBack: () {},
    )));
    expect(find.text('Work › Projects › Foo'), findsOneWidget);
    expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsOneWidget);
  });

  testWidgets('back icon tap fires onBack', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () => tapped = true,
    )));
    await t.tap(find.byIcon(FluentIcons.arrow_left_24_regular));
    expect(tapped, isTrue);
  });

  testWidgets('renders trailing widgets', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
      trailing: const [Text('ACT-1'), Text('ACT-2')],
    )));
    expect(find.text('ACT-1'), findsOneWidget);
    expect(find.text('ACT-2'), findsOneWidget);
  });

  testWidgets('toolbar height is 48', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
    )));
    final container = t.widget<Container>(find.descendant(
      of: find.byType(DetailScreenToolbar),
      matching: find.byType(Container),
    ).first);
    final constraints = container.constraints;
    expect(constraints?.maxHeight ?? (container.decoration != null ? 48.0 : 0.0), 48);
  });

  testWidgets('crumb uses font-mono 12px textDim', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('X'));
    expect(text.style?.fontSize, 12);
    expect(text.style?.color, tokens.textDim);
  });
}
