import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/search/models/search_result.dart';
import 'package:twmt/services/search/utils/regex_query_builder.dart';

void main() {
  group('RegexQueryBuilder date filters use Unix SECONDS (matching *_at columns)',
      () {
    // All *_at columns store Unix timestamps in SECONDS (writers use
    // `DateTime.now().millisecondsSinceEpoch ~/ 1000`). Emitting milliseconds
    // would make minDate exclude every row and maxDate an always-true no-op.
    //
    // Non-zero ms remainders (.123/.456) ensure the ms and seconds values
    // differ in more than trailing zeros, so the isNot(contains(ms))
    // assertions below are meaningful.
    final minDate = DateTime.fromMillisecondsSinceEpoch(1700000000123, isUtc: true);
    final maxDate = DateTime.fromMillisecondsSinceEpoch(1800000000456, isUtc: true);
    final filter = SearchFilter(minDate: minDate, maxDate: maxDate);

    test('regex (LIKE fallback) query compares created_at in seconds', () {
      final sql = RegexQueryBuilder.buildRegexQuery(
        'cavalry',
        searchIn: 'both',
        filter: filter,
        limit: 10,
      );
      expect(sql, matches(RegExp(r'tu\.created_at >= 1700000000(?!\d)')));
      expect(sql, matches(RegExp(r'tu\.created_at <= 1800000000(?!\d)')));
      expect(sql, isNot(contains('1700000000123')));
      expect(sql, isNot(contains('1800000000456')));
    });
  });

  group('RegexQueryBuilder deterministic ordering', () {
    test('orders by a unique column (tu.id) for stable results', () {
      final sql = RegexQueryBuilder.buildRegexQuery(
        'cavalry',
        searchIn: 'both',
        limit: 10,
      );
      expect(sql, matches(RegExp(r'ORDER\s+BY\s+tu\.id')));
    });
  });
}
