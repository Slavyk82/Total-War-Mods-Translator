import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/settings/widgets/language_settings_data_source.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

Language _lang(String code, {bool custom = false}) => Language(
      id: 'id-$code',
      code: code,
      name: code.toUpperCase(),
      nativeName: code,
      isCustom: custom,
    );

LanguageSettingsDataSource _source(
  List<Language> languages, {
  String defaultCode = 'en',
  void Function(Language)? onSetDefault,
  void Function(Language)? onDelete,
}) =>
    LanguageSettingsDataSource(
      languages: languages,
      defaultLanguageCode: defaultCode,
      tokens: slateTokens,
      onSetDefault: onSetDefault ?? (_) {},
      onDelete: onDelete ?? (_) {},
    );

// Pumps a single built cell inside a theme that carries the TWMT tokens,
// required because the custom-language action button reads context.tokens.
Future<void> _pumpCell(WidgetTester tester, Widget cell) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.light().copyWith(extensions: [slateTokens]),
      home: Scaffold(body: Center(child: cell)),
    ),
  );
}

void main() {
  group('rows mapping', () {
    test('builds one row per language with the expected cell values', () {
      final langs = [_lang('en'), _lang('de', custom: true)];
      final source = _source(langs);

      expect(source.rows, hasLength(2));

      final cells = source.rows[1].getCells();
      expect(cells[0].columnName, 'default');
      expect(cells[0].value, langs[1]);
      expect(cells[1].value, 'de'); // code
      expect(cells[2].value, 'DE (de)'); // displayName
      expect(cells[3].columnName, 'actions');
      expect(cells[3].value, langs[1]);
    });
  });

  group('default cell', () {
    testWidgets('tapping it sets that language as default', (tester) async {
      Language? chosen;
      final langs = [_lang('en'), _lang('fr')];
      final source = _source(langs, onSetDefault: (l) => chosen = l);

      final adapter = source.buildRow(source.rows[1]); // 'fr' row
      await _pumpCell(tester, adapter.cells.first);

      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(chosen?.code, 'fr');
    });

    testWidgets('shows a filled radio for the default language only',
        (tester) async {
      final source = _source([_lang('en')], defaultCode: 'en');

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.first);

      expect(
        find.byIcon(FluentIcons.radio_button_24_filled),
        findsOneWidget,
      );
    });

    testWidgets('shows a regular radio for a non-default language',
        (tester) async {
      final source = _source([_lang('fr')], defaultCode: 'en');

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.first);

      expect(
        find.byIcon(FluentIcons.radio_button_24_regular),
        findsOneWidget,
      );
    });
  });

  group('actions cell', () {
    testWidgets('is empty for a non-custom language', (tester) async {
      final source = _source([_lang('en')]); // not custom

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.last);

      expect(find.byIcon(FluentIcons.delete_24_regular), findsNothing);
    });

    testWidgets('deletes a custom language when its delete button is tapped',
        (tester) async {
      Language? deleted;
      final source =
          _source([_lang('zz', custom: true)], onDelete: (l) => deleted = l);

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.last);

      expect(find.byIcon(FluentIcons.delete_24_regular), findsOneWidget);
      await tester.tap(find.byIcon(FluentIcons.delete_24_regular));
      await tester.pump();

      expect(deleted?.code, 'zz');
    });
  });
}
