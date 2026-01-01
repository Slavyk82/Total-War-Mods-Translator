import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/providers/statistics/translation_statistics_provider.dart';

void main() {
  group('TranslationStats', () {
    test('initial state has correct defaults', () {
      const stats = TranslationStats(
        totalTranslations: 0,
        translationsToday: 0,
        lastTranslationAt: null,
      );

      expect(stats.totalTranslations, 0);
      expect(stats.translationsToday, 0);
      expect(stats.lastTranslationAt, isNull);
    });

    test('copyWith creates new state with updated values', () {
      const stats = TranslationStats(
        totalTranslations: 0,
        translationsToday: 0,
        lastTranslationAt: null,
      );

      final now = DateTime.now();
      final newStats = stats.copyWith(
        totalTranslations: 100,
        translationsToday: 25,
        lastTranslationAt: now,
      );

      expect(newStats.totalTranslations, 100);
      expect(newStats.translationsToday, 25);
      expect(newStats.lastTranslationAt, now);
    });

    test('copyWith preserves values when not specified', () {
      final now = DateTime.now();
      final stats = TranslationStats(
        totalTranslations: 100,
        translationsToday: 25,
        lastTranslationAt: now,
      );

      final newStats = stats.copyWith(totalTranslations: 150);

      expect(newStats.totalTranslations, 150);
      expect(newStats.translationsToday, 25);
      expect(newStats.lastTranslationAt, now);
    });

    group('hasTranslations', () {
      test('returns false when totalTranslations is 0', () {
        const stats = TranslationStats(
          totalTranslations: 0,
          translationsToday: 0,
        );

        expect(stats.hasTranslations, isFalse);
      });

      test('returns true when totalTranslations > 0', () {
        const stats = TranslationStats(
          totalTranslations: 1,
          translationsToday: 0,
        );

        expect(stats.hasTranslations, isTrue);
      });
    });

    group('hasTranslationsToday', () {
      test('returns false when translationsToday is 0', () {
        const stats = TranslationStats(
          totalTranslations: 100,
          translationsToday: 0,
        );

        expect(stats.hasTranslationsToday, isFalse);
      });

      test('returns true when translationsToday > 0', () {
        const stats = TranslationStats(
          totalTranslations: 100,
          translationsToday: 5,
        );

        expect(stats.hasTranslationsToday, isTrue);
      });
    });

    group('timeSinceLastTranslation', () {
      test('returns null when lastTranslationAt is null', () {
        const stats = TranslationStats(
          totalTranslations: 100,
          translationsToday: 5,
          lastTranslationAt: null,
        );

        expect(stats.timeSinceLastTranslation, isNull);
      });

      test('returns duration since last translation', () {
        final lastTranslation = DateTime.now().subtract(
          const Duration(minutes: 30),
        );
        final stats = TranslationStats(
          totalTranslations: 100,
          translationsToday: 5,
          lastTranslationAt: lastTranslation,
        );

        final duration = stats.timeSinceLastTranslation;

        expect(duration, isNotNull);
        expect(duration!.inMinutes, greaterThanOrEqualTo(30));
      });

      test('returns small duration for recent translation', () {
        final lastTranslation = DateTime.now().subtract(
          const Duration(seconds: 5),
        );
        final stats = TranslationStats(
          totalTranslations: 100,
          translationsToday: 5,
          lastTranslationAt: lastTranslation,
        );

        final duration = stats.timeSinceLastTranslation;

        expect(duration, isNotNull);
        expect(duration!.inSeconds, greaterThanOrEqualTo(5));
        expect(duration.inSeconds, lessThan(10));
      });
    });
  });

  group('TranslationStatisticsNotifier - State Model Tests', () {
    // Since the notifier depends on event stream providers which require EventBus,
    // we test the state model behavior in isolation.

    test('stats with multiple translations', () {
      final now = DateTime.now();
      final stats = TranslationStats(
        totalTranslations: 500,
        translationsToday: 50,
        lastTranslationAt: now,
      );

      expect(stats.hasTranslations, isTrue);
      expect(stats.hasTranslationsToday, isTrue);
      expect(stats.timeSinceLastTranslation, isNotNull);
    });

    test('stats accumulation simulation', () {
      // Simulate how stats would be accumulated
      var stats = const TranslationStats(
        totalTranslations: 0,
        translationsToday: 0,
      );

      // Simulate adding translations
      for (var i = 0; i < 10; i++) {
        stats = stats.copyWith(
          totalTranslations: stats.totalTranslations + 1,
          translationsToday: stats.translationsToday + 1,
          lastTranslationAt: DateTime.now(),
        );
      }

      expect(stats.totalTranslations, 10);
      expect(stats.translationsToday, 10);
    });

    test('daily stats reset simulation', () {
      final stats = TranslationStats(
        totalTranslations: 500,
        translationsToday: 50,
        lastTranslationAt: DateTime.now(),
      );

      // Simulate resetDailyStats
      final resetStats = stats.copyWith(translationsToday: 0);

      expect(resetStats.totalTranslations, 500); // Total preserved
      expect(resetStats.translationsToday, 0); // Today reset
      expect(resetStats.lastTranslationAt, isNotNull); // Last preserved
    });

    test('batch completion adds multiple translations', () {
      var stats = const TranslationStats(
        totalTranslations: 100,
        translationsToday: 10,
      );

      // Simulate batch completion with 25 units
      const completedUnits = 25;
      stats = stats.copyWith(
        totalTranslations: stats.totalTranslations + completedUnits,
        translationsToday: stats.translationsToday + completedUnits,
        lastTranslationAt: DateTime.now(),
      );

      expect(stats.totalTranslations, 125);
      expect(stats.translationsToday, 35);
    });

    test('handles translations from previous days', () {
      // Translation from yesterday
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final stats = TranslationStats(
        totalTranslations: 100,
        translationsToday: 0, // No translations today
        lastTranslationAt: yesterday,
      );

      expect(stats.hasTranslations, isTrue);
      expect(stats.hasTranslationsToday, isFalse);
      expect(
        stats.timeSinceLastTranslation!.inHours,
        greaterThanOrEqualTo(24),
      );
    });
  });

  group('TranslationStats edge cases', () {
    test('handles large numbers', () {
      final stats = TranslationStats(
        totalTranslations: 1000000,
        translationsToday: 50000,
        lastTranslationAt: DateTime.now(),
      );

      expect(stats.hasTranslations, isTrue);
      expect(stats.totalTranslations, 1000000);
    });

    test('handles zero values correctly', () {
      const stats = TranslationStats(
        totalTranslations: 0,
        translationsToday: 0,
        lastTranslationAt: null,
      );

      expect(stats.hasTranslations, isFalse);
      expect(stats.hasTranslationsToday, isFalse);
      expect(stats.timeSinceLastTranslation, isNull);
    });

    test('translationsToday can be less than total', () {
      const stats = TranslationStats(
        totalTranslations: 1000,
        translationsToday: 10,
      );

      expect(stats.totalTranslations > stats.translationsToday, isTrue);
    });

    test('time calculations near midnight', () {
      // Test with a time near midnight
      final nearMidnight = DateTime(
        DateTime.now().year,
        DateTime.now().month,
        DateTime.now().day,
        23,
        59,
        59,
      );

      final stats = TranslationStats(
        totalTranslations: 100,
        translationsToday: 10,
        lastTranslationAt: nearMidnight,
      );

      expect(stats.timeSinceLastTranslation, isNotNull);
    });
  });
}
