import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/utils/workshop_url_parser.dart';

void main() {
  group('parseWorkshopId', () {
    test('extracts the id from a full community URL', () {
      expect(
          parseWorkshopId(
              'https://steamcommunity.com/sharedfiles/filedetails/?id=3456789012'),
          '3456789012');
    });

    test('extracts the id from a bare URL without scheme', () {
      expect(
          parseWorkshopId(
              'steamcommunity.com/sharedfiles/filedetails/?id=3456789012'),
          '3456789012');
    });

    test('accepts a bare numeric id', () {
      expect(parseWorkshopId('3456789012'), '3456789012');
    });

    test('accepts a numeric id surrounded by whitespace', () {
      expect(parseWorkshopId('  3456789012  '), '3456789012');
    });

    test('returns null on empty input', () {
      expect(parseWorkshopId(''), isNull);
      expect(parseWorkshopId('   '), isNull);
    });

    test('returns null on non-numeric input without an id query param', () {
      expect(parseWorkshopId('not a url'), isNull);
    });

    test('returns null on URLs without an id param', () {
      expect(parseWorkshopId('https://steamcommunity.com/sharedfiles/'),
          isNull);
    });

    test('returns null on URLs with non-numeric id', () {
      expect(
          parseWorkshopId(
              'https://steamcommunity.com/sharedfiles/filedetails/?id=abc'),
          isNull);
    });
  });
}
