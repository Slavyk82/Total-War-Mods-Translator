import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_cover.dart';

void main() {
  Widget wrap(Widget child, {bool forge = false}) => MaterialApp(
        theme: forge ? AppTheme.forgeDarkTheme : AppTheme.atelierDarkTheme,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders monogram when imageUrl is null', (t) async {
    await t.pumpWidget(wrap(
      const DetailCover(imageUrl: null, monogramFallback: 'WH'),
    ));
    expect(find.text('WH'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('renders Image.network when imageUrl is provided', (t) async {
    await t.pumpWidget(wrap(
      const DetailCover(
        imageUrl: 'https://example.com/thumb.jpg',
        monogramFallback: 'WH',
      ),
    ));
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('monogram uses Instrument Serif italic under Atelier', (t) async {
    await t.pumpWidget(wrap(
      const DetailCover(imageUrl: null, monogramFallback: 'WH'),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('WH'));
    expect(text.style?.fontStyle,
        tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal);
    expect(text.style?.color, tokens.accent);
  });

  testWidgets('monogram drops italic under Forge', (t) async {
    await t.pumpWidget(wrap(
      const DetailCover(imageUrl: null, monogramFallback: 'WH'),
      forge: true,
    ));
    final text = t.widget<Text>(find.text('WH'));
    expect(text.style?.fontStyle, FontStyle.normal);
  });

  testWidgets('cover has 110×68 dimensions', (t) async {
    await t.pumpWidget(wrap(
      const DetailCover(imageUrl: null, monogramFallback: 'X'),
    ));
    final sized = t.widget<SizedBox>(find.byType(SizedBox).first);
    expect(sized.width, 110);
    expect(sized.height, 68);
  });
}
