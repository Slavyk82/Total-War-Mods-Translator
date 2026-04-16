import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/widgets/lists/relative_date.dart';

void main() {
  final now = DateTime(2026, 4, 16, 12, 0);

  group('formatRelativeSince', () {
    test('returns null for null input', () {
      expect(formatRelativeSince(null, now: now), isNull);
    });

    test('reports under-one-hour deltas with the `< 1h` sentinel', () {
      final date = now.subtract(const Duration(minutes: 15));
      expect(formatRelativeSince(date, now: now), '< 1h');
    });

    test('reports hourly deltas within the same day', () {
      final date = now.subtract(const Duration(hours: 5));
      expect(formatRelativeSince(date, now: now), '5h');
    });

    test('pluralises day deltas below one month', () {
      expect(formatRelativeSince(now.subtract(const Duration(days: 1)),
          now: now), '1 day');
      expect(formatRelativeSince(now.subtract(const Duration(days: 12)),
          now: now), '12 days');
    });

    test('reports month deltas below one year', () {
      expect(formatRelativeSince(now.subtract(const Duration(days: 30)),
          now: now), '1 month');
      expect(formatRelativeSince(now.subtract(const Duration(days: 90)),
          now: now), '3 months');
    });

    test('reports year deltas from 365 days onward', () {
      expect(formatRelativeSince(now.subtract(const Duration(days: 365)),
          now: now), '1 year');
      expect(formatRelativeSince(now.subtract(const Duration(days: 730)),
          now: now), '2 years');
    });

    test('future dates collapse to the same-day `< 1h` branch', () {
      // Diffs from `now` to a future date are negative; inDays/inHours both
      // return 0 at the sub-hour boundary, so the function falls into the
      // `< 1h` bucket rather than emitting a misleading "-5 days" label.
      final future = now.add(const Duration(minutes: 30));
      expect(formatRelativeSince(future, now: now), '< 1h');
    });
  });

  group('formatAbsoluteDate', () {
    test('returns null for null input', () {
      expect(formatAbsoluteDate(null), isNull);
    });

    test('pads day, month, hour and minute to two digits', () {
      final date = DateTime(2026, 4, 3, 7, 5);
      expect(formatAbsoluteDate(date), '03/04/2026 07:05');
    });

    test('formats dates with two-digit day/month without leading zeros loss',
        () {
      final date = DateTime(2025, 12, 31, 23, 59);
      expect(formatAbsoluteDate(date), '31/12/2025 23:59');
    });
  });
}
