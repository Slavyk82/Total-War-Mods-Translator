import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/settings/widgets/ignored_source_texts_data_source.dart';
import 'package:twmt/models/domain/ignored_source_text.dart';
import 'package:twmt/theme/tokens/slate_tokens.dart';

IgnoredSourceText _text(String source, {bool enabled = true}) =>
    IgnoredSourceText(
      id: 'id-$source',
      sourceText: source,
      isEnabled: enabled,
      createdAt: 0,
      updatedAt: 0,
    );

IgnoredSourceTextsDataSource _source(
  List<IgnoredSourceText> texts, {
  void Function(IgnoredSourceText)? onEdit,
  void Function(IgnoredSourceText)? onDelete,
  void Function(IgnoredSourceText)? onToggleEnabled,
}) =>
    IgnoredSourceTextsDataSource(
      texts: texts,
      tokens: slateTokens,
      onEdit: onEdit ?? (_) {},
      onDelete: onDelete ?? (_) {},
      onToggleEnabled: onToggleEnabled ?? (_) {},
    );

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
    test('builds one row per text with enabled/source/actions cells', () {
      final texts = [_text('foo'), _text('bar', enabled: false)];
      final source = _source(texts);

      expect(source.rows, hasLength(2));

      final cells = source.rows[1].getCells();
      expect(cells[0].columnName, 'enabled');
      expect(cells[0].value, false);
      expect(cells[1].value, 'bar');
      expect(cells[2].columnName, 'actions');
      expect(cells[2].value, texts[1]);
    });
  });

  group('enabled cell', () {
    testWidgets('tapping it toggles the row it belongs to', (tester) async {
      IgnoredSourceText? toggled;
      final source =
          _source([_text('foo'), _text('bar')], onToggleEnabled: (t) => toggled = t);

      await _pumpCell(tester, source.buildRow(source.rows[1]).cells.first);
      await tester.tap(find.byType(GestureDetector));
      await tester.pump();

      expect(toggled?.sourceText, 'bar');
    });

    testWidgets('renders a checked box when enabled', (tester) async {
      final source = _source([_text('foo', enabled: true)]);

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.first);

      expect(find.byIcon(FluentIcons.checkbox_checked_24_filled),
          findsOneWidget);
    });

    testWidgets('renders an unchecked box when disabled', (tester) async {
      final source = _source([_text('foo', enabled: false)]);

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.first);

      expect(find.byIcon(FluentIcons.checkbox_unchecked_24_regular),
          findsOneWidget);
    });
  });

  group('actions cell', () {
    testWidgets('edit button invokes onEdit', (tester) async {
      IgnoredSourceText? edited;
      final source = _source([_text('foo')], onEdit: (t) => edited = t);

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.last);
      await tester.tap(find.byIcon(FluentIcons.edit_24_regular));
      await tester.pump();

      expect(edited?.sourceText, 'foo');
    });

    testWidgets('delete button invokes onDelete', (tester) async {
      IgnoredSourceText? deleted;
      final source = _source([_text('foo')], onDelete: (t) => deleted = t);

      await _pumpCell(tester, source.buildRow(source.rows[0]).cells.last);
      await tester.tap(find.byIcon(FluentIcons.delete_24_regular));
      await tester.pump();

      expect(deleted?.sourceText, 'foo');
    });
  });
}
