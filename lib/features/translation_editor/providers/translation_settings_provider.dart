import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Translation batch settings
///
/// [unitsPerBatch]: Number of units per batch. 0 = auto (calculated based on tokens)
/// [skipTranslationMemory]: If true, skip TM lookup during translation (use LLM only)
class TranslationSettings {
  final int unitsPerBatch;
  final int parallelBatches;
  final bool skipTranslationMemory;

  const TranslationSettings({
    required this.unitsPerBatch,
    required this.parallelBatches,
    this.skipTranslationMemory = false,
  });

  /// Whether auto mode is enabled (unitsPerBatch = 0)
  bool get isAutoMode => unitsPerBatch == 0;

  @override
  String toString() => 'TranslationSettings(units: ${isAutoMode ? "auto" : unitsPerBatch}, parallel: $parallelBatches, skipTM: $skipTranslationMemory)';
}

/// Simple state provider for translation settings
class TranslationSettingsNotifier extends Notifier<TranslationSettings> {
  bool _isLoaded = false;
  
  @override
  TranslationSettings build() {
    // Load settings asynchronously and update state when done
    _loadSettings();
    // Return default values initially (0 = auto mode)
    // Note: skipTranslationMemory is NOT persisted - it resets on project exit
    return const TranslationSettings(
      unitsPerBatch: 0,
      parallelBatches: 5,
      skipTranslationMemory: false,
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
    // 0 = auto mode (default)
    final unitsPerBatch = prefs.getInt('translation_units_per_batch') ?? 0;
    // Limit parallelBatches to 1-5 range for safety
    final savedParallel = prefs.getInt('translation_parallel_batches') ?? 5;
    final parallelBatches = savedParallel.clamp(1, 5);
    // skipTranslationMemory is NOT loaded from prefs - always starts as false

    debugPrint('[TranslationSettings] Loaded from prefs: units=$unitsPerBatch, parallel=$parallelBatches');

    state = TranslationSettings(
      unitsPerBatch: unitsPerBatch,
      parallelBatches: parallelBatches,
      skipTranslationMemory: false, // Always false on load
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
      skipTranslationMemory: state.skipTranslationMemory, // Preserve current session value
    );
  }

  /// Toggle skipTranslationMemory setting (session-only, not persisted)
  void setSkipTranslationMemory(bool value) {
    state = TranslationSettings(
      unitsPerBatch: state.unitsPerBatch,
      parallelBatches: state.parallelBatches,
      skipTranslationMemory: value,
    );
  }
}

/// Provider for translation settings
final translationSettingsProvider = NotifierProvider<TranslationSettingsNotifier, TranslationSettings>(() {
  return TranslationSettingsNotifier();
});

