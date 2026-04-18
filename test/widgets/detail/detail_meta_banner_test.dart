import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/detail_cover.dart';
import 'package:twmt/widgets/detail/detail_meta_banner.dart';

void main() {
  Widget wrap(Widget child, {bool forge = false}) => MaterialApp(
        theme: forge ? AppTheme.forgeDarkTheme : AppTheme.atelierDarkTheme,
        home: Scaffold(body: child),
      );

  testWidgets('renders title, subtitle segments and cover', (t) async {
    await t.pumpWidget(wrap(
      const DetailMetaBanner(
        cover: DetailCover(imageUrl: null, monogramFallback: 'WH'),
        title: 'Warhammer III — FR',
        subtitle: [Text('mod'), Text('steam 123'), Text('3 languages')],
      ),
    ));
    expect(find.text('Warhammer III — FR'), findsOneWidget);
    expect(find.text('mod'), findsOneWidget);
    expect(find.text('steam 123'), findsOneWidget);
    expect(find.text('3 languages'), findsOneWidget);
    expect(find.byType(DetailCover), findsOneWidget);
  });

  testWidgets('renders actions on the right', (t) async {
    await t.pumpWidget(wrap(
      DetailMetaBanner(
        cover: const DetailCover(imageUrl: null, monogramFallback: 'X'),
        title: 'Name',
        subtitle: const [Text('sub')],
        actions: [
          ElevatedButton(onPressed: () {}, child: const Text('ACT-1')),
          ElevatedButton(onPressed: () {}, child: const Text('ACT-2')),
        ],
      ),
    ));
    expect(find.text('ACT-1'), findsOneWidget);
    expect(find.text('ACT-2'), findsOneWidget);
  });

  testWidgets('renders description when provided', (t) async {
    await t.pumpWidget(wrap(
      const DetailMetaBanner(
        cover: DetailCover(imageUrl: null, monogramFallback: 'X'),
        title: 'Name',
        subtitle: [Text('sub')],
        description: 'A long descriptive paragraph.',
      ),
    ));
    expect(find.text('A long descriptive paragraph.'), findsOneWidget);
  });

  testWidgets('omits description when null', (t) async {
    await t.pumpWidget(wrap(
      const DetailMetaBanner(
        cover: DetailCover(imageUrl: null, monogramFallback: 'X'),
        title: 'Name',
        subtitle: [Text('sub')],
      ),
    ));
    expect(find.byKey(const Key('detail-meta-banner-description')), findsNothing);
  });

  testWidgets('title uses fontDisplay with italic in Atelier', (t) async {
    await t.pumpWidget(wrap(
      const DetailMetaBanner(
        cover: DetailCover(imageUrl: null, monogramFallback: 'X'),
        title: 'T',
        subtitle: [Text('s')],
      ),
    ));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('T'));
    expect(text.style?.fontStyle,
        tokens.fontDisplayItalic ? FontStyle.italic : FontStyle.normal);
    expect(text.style?.color, tokens.text);
  });

  testWidgets('omits cover when null', (t) async {
    await t.pumpWidget(wrap(
      const DetailMetaBanner(
        title: 'Name',
        subtitle: [Text('sub')],
      ),
    ));
    expect(find.byType(DetailCover), findsNothing);
    expect(find.text('Name'), findsOneWidget);
    expect(find.text('sub'), findsOneWidget);
  });
}
