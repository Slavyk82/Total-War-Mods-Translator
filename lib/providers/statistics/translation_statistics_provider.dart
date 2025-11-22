import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../events/event_stream_providers.dart';

part 'translation_statistics_provider.g.dart';

/// Real-time translation statistics that update as events occur
@riverpod
class TranslationStatistics extends _$TranslationStatistics {
  @override
  TranslationStats build() {
    final initialStats = TranslationStats(
      totalTranslations: 0,
      translationsToday: 0,
      lastTranslationAt: null,
    );

    _listenToEvents();

    return initialStats;
  }

  void _listenToEvents() {
    ref.listen(
      translationAddedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          final now = DateTime.now();
          final isToday = event.timestamp.year == now.year &&
              event.timestamp.month == now.month &&
              event.timestamp.day == now.day;

          state = state.copyWith(
            totalTranslations: state.totalTranslations + 1,
            translationsToday:
                isToday ? state.translationsToday + 1 : state.translationsToday,
            lastTranslationAt: event.timestamp,
          );
        }
      },
    );

    // Also listen to batch completions for aggregate stats
    ref.listen(
      batchCompletedEventsProvider,
      (previous, next) {
        if (next.hasValue) {
          final event = next.value!;
          final now = DateTime.now();
          final isToday = event.timestamp.year == now.year &&
              event.timestamp.month == now.month &&
              event.timestamp.day == now.day;

          state = state.copyWith(
            totalTranslations:
                state.totalTranslations + event.completedUnits,
            translationsToday: isToday
                ? state.translationsToday + event.completedUnits
                : state.translationsToday,
            lastTranslationAt: event.timestamp,
          );
        }
      },
    );
  }

  /// Reset daily statistics (call at midnight)
  void resetDailyStats() {
    state = state.copyWith(translationsToday: 0);
  }
}

class TranslationStats {
  final int totalTranslations;
  final int translationsToday;
  final DateTime? lastTranslationAt;

  const TranslationStats({
    required this.totalTranslations,
    required this.translationsToday,
    this.lastTranslationAt,
  });

  TranslationStats copyWith({
    int? totalTranslations,
    int? translationsToday,
    DateTime? lastTranslationAt,
  }) {
    return TranslationStats(
      totalTranslations: totalTranslations ?? this.totalTranslations,
      translationsToday: translationsToday ?? this.translationsToday,
      lastTranslationAt: lastTranslationAt ?? this.lastTranslationAt,
    );
  }

  /// Check if there are any translations
  bool get hasTranslations => totalTranslations > 0;

  /// Check if there were translations today
  bool get hasTranslationsToday => translationsToday > 0;

  /// Get time since last translation
  Duration? get timeSinceLastTranslation {
    if (lastTranslationAt == null) return null;
    return DateTime.now().difference(lastTranslationAt!);
  }
}
