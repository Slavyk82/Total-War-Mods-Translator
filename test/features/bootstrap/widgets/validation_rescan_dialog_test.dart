import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/bootstrap/widgets/validation_rescan_dialog.dart';

void main() {
  group('formatDuration', () {
    test('seconds only under 1 min', () {
      expect(formatDuration(const Duration(seconds: 45)), '45s');
    });
    test('minutes + seconds when under 1h', () {
      expect(
        formatDuration(const Duration(minutes: 3, seconds: 20)),
        '3m 20s',
      );
    });
    test('hours + minutes when >= 1h', () {
      expect(
        formatDuration(const Duration(hours: 1, minutes: 5, seconds: 30)),
        '1h 5m',
      );
    });
  });

  group('formatCount', () {
    test('inserts thousands separators', () {
      expect(formatCount(0), '0');
      expect(formatCount(999), '999');
      expect(formatCount(1000), '1,000');
      expect(formatCount(12000), '12,000');
      expect(formatCount(1234567), '1,234,567');
    });

    test('handles negative values', () {
      expect(formatCount(-1234), '-1,234');
    });
  });
}
