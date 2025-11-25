import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Translation batch settings
class TranslationSettings {
  final int unitsPerBatch;
  final int parallelBatches;

  const TranslationSettings({
    required this.unitsPerBatch,
    required this.parallelBatches,
  });
  
  @override
  String toString() => 'TranslationSettings(units: $unitsPerBatch, parallel: $parallelBatches)';
}

/// Simple state provider for translation settings
class TranslationSettingsNotifier extends Notifier<TranslationSettings> {
  bool _isLoaded = false;
  
  @override
  TranslationSettings build() {
    // Load settings asynchronously and update state when done
    _loadSettings();
    // Return default values initially
    return const TranslationSettings(
      unitsPerBatch: 100,
      parallelBatches: 3,
    );
  }

  /// Ensure settings are loaded before reading
  Future<TranslationSettings> ensureLoaded() async {
    if (!_isLoaded) {
      await _loadSettings();
    }
    return state;
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final unitsPerBatch = prefs.getInt('translation_units_per_batch') ?? 100;
    // Limit parallelBatches to 1-5 range for safety
    final savedParallel = prefs.getInt('translation_parallel_batches') ?? 3;
    final parallelBatches = savedParallel.clamp(1, 5);

    debugPrint('[TranslationSettings] Loaded from prefs: units=$unitsPerBatch, parallel=$parallelBatches');

    state = TranslationSettings(
      unitsPerBatch: unitsPerBatch,
      parallelBatches: parallelBatches,
    );
    _isLoaded = true;
  }

  Future<void> updateSettings({
    required int unitsPerBatch,
    required int parallelBatches,
  }) async {
    // Limit parallelBatches to 1-5 range for safety
    final safeParallelBatches = parallelBatches.clamp(1, 5);

    debugPrint('[TranslationSettings] Saving: units=$unitsPerBatch, parallel=$safeParallelBatches');

    final prefs = await SharedPreferences.getInstance();
    final success1 = await prefs.setInt('translation_units_per_batch', unitsPerBatch);
    final success2 = await prefs.setInt('translation_parallel_batches', safeParallelBatches);

    debugPrint('[TranslationSettings] Save result: units=$success1, parallel=$success2');

    state = TranslationSettings(
      unitsPerBatch: unitsPerBatch,
      parallelBatches: safeParallelBatches,
    );
  }
}

/// Provider for translation settings
final translationSettingsProvider = NotifierProvider<TranslationSettingsNotifier, TranslationSettings>(() {
  return TranslationSettingsNotifier();
});

