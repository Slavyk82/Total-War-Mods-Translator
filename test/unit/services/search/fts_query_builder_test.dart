import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/search/utils/fts_query_builder.dart';

void main() {
  group('FtsQueryBuilder.buildGlossaryQuery LIKE escaping', () {
    test('escapes percent sign in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        '50%',
        limit: 10,
      );
      // Must escape % and include ESCAPE clause
      expect(sql, contains(r"'%50\%%'"));
      expect(sql.toUpperCase(), contains("ESCAPE '\\'"));
    });

    test('escapes underscore in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        'foo_bar',
        limit: 10,
      );
      expect(sql, contains(r"'%foo\_bar%'"));
    });

    test('escapes backslash in user input', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        r'path\file',
        limit: 10,
      );
      expect(sql, contains(r"'%path\\file%'"));
    });

    test('still escapes single quote', () {
      final sql = FtsQueryBuilder.buildGlossaryQuery(
        "O'Brien",
        limit: 10,
      );
      expect(sql, contains("'%O''Brien%'"));
    });
  });
}
