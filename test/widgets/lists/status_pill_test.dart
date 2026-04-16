import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/lists/status_pill.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('StatusPill renders label + uses supplied colors, radiusMd',
      (t) async {
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    await t.pumpWidget(wrap(
      StatusPill(
        label: 'Imported',
        foreground: tokens.ok,
        background: tokens.okBg,
      ),
    ));
    expect(find.text('Imported'), findsOneWidget);

    final container = t.widget<Container>(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
      ),
    );
    final deco = container.decoration as BoxDecoration;
    expect(deco.color, tokens.okBg);
    expect(
      deco.borderRadius,
      BorderRadius.circular(tokens.radiusMd),
    );
    // Border color is the foreground tinted at 0.4 alpha.
    expect(
      (deco.border as Border).top.color,
      tokens.ok.withValues(alpha: 0.4),
    );
  });

  testWidgets('StatusPill renders icon when provided', (t) async {
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    await t.pumpWidget(wrap(
      StatusPill(
        label: 'Err',
        foreground: tokens.err,
        background: tokens.errBg,
        icon: Icons.warning,
      ),
    ));
    expect(find.byIcon(Icons.warning), findsOneWidget);
  });

  testWidgets('StatusPill fires onTap when set', (t) async {
    var tapped = false;
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    await t.pumpWidget(wrap(
      StatusPill(
        label: 'Click',
        foreground: tokens.err,
        background: tokens.errBg,
        onTap: () => tapped = true,
      ),
    ));
    await t.tap(find.byType(StatusPill));
    expect(tapped, isTrue);
  });

  testWidgets('StatusPill wraps in Tooltip when tooltip is set', (t) async {
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    await t.pumpWidget(wrap(
      StatusPill(
        label: 'Hi',
        foreground: tokens.ok,
        background: tokens.okBg,
        tooltip: 'Extra info',
      ),
    ));
    expect(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Extra info',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('StatusPill has no Tooltip ancestor when tooltip is null',
      (t) async {
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    await t.pumpWidget(wrap(
      StatusPill(
        label: 'Hi',
        foreground: tokens.ok,
        background: tokens.okBg,
      ),
    ));
    expect(
      find.descendant(
        of: find.byType(StatusPill),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
  });
}
