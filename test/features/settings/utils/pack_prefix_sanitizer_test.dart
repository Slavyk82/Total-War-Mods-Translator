import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/utils/pack_prefix_sanitizer.dart';

void main() {
  group('sanitizePackPrefix', () {
    test('removes Windows-illegal filename characters', () {
      expect(sanitizePackPrefix(r'a/b\c:d*e?f"g<h>i|j'), 'abcdefghij');
    });

    test('keeps exclamation marks and underscores', () {
      expect(sanitizePackPrefix('!!!!!!!!!!_'), '!!!!!!!!!!_');
    });

    test('allows an empty string', () {
      expect(sanitizePackPrefix(''), '');
    });

    test('leaves a normal custom prefix untouched', () {
      expect(sanitizePackPrefix('zzz_mygroup'), 'zzz_mygroup');
    });
  });
}
