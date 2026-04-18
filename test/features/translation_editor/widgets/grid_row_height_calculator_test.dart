import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/grid_row_height_calculator.dart';

void main() {
  setUp(rowHeightCache.clear);

  group('rowHeightCache', () {
    test('caches by (text, width) and returns the same value', () {
      final h1 = calculateTextHeight('hello world', 200);
      final h2 = calculateTextHeight('hello world', 200);
      expect(h1, h2);
      expect(rowHeightCache.length, 1);
    });

    test('different widths produce separate cache entries', () {
      calculateTextHeight('same text', 200);
      calculateTextHeight('same text', 300);
      expect(rowHeightCache.length, 2);
    });

    test('clear() empties the cache', () {
      calculateTextHeight('x', 100);
      expect(rowHeightCache.length, 1);
      rowHeightCache.clear();
      expect(rowHeightCache.length, 0);
    });

    test('evicts oldest entries past the cap', () {
      for (var i = 0; i < rowHeightCacheMaxEntries + 50; i++) {
        calculateTextHeight('text $i', 100);
      }
      expect(rowHeightCache.length, lessThanOrEqualTo(rowHeightCacheMaxEntries));
    });
  });
}
