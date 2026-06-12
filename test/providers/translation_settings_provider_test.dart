import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/providers/translation_settings_provider.dart';

/// Tests for [TranslationSettingsNotifier] / [translationSettingsProvider].
///
/// This provider talks to [SharedPreferences] directly (no injected service),
/// so dependencies are faked with `SharedPreferences.setMockInitialValues`
/// rather than mocktail. The notifier is a synchronous `Notifier` whose
/// `build()` returns defaults immediately and kicks off an async `_loadSettings`
/// microtask; `ensureLoaded()` is the deterministic way to await that load.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const kUnitsKey = 'translation_units_per_batch';
  const kParallelKey = 'translation_parallel_batches';

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('build()', () {
    test('returns synchronous defaults before async load completes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Read state synchronously right after build() — the async _loadSettings
      // microtask has not been awaited yet, so we see the hard-coded defaults.
      final initial = container.read(translationSettingsProvider);
      expect(initial.unitsPerBatch, 0);
      expect(initial.parallelBatches, 5);
      expect(initial.skipTranslationMemory, isFalse);
      expect(initial.isAutoMode, isTrue);
    });

    test('async load keeps defaults when prefs are empty', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loaded =
          await container.read(translationSettingsProvider.notifier).ensureLoaded();

      expect(loaded.unitsPerBatch, 0);
      expect(loaded.parallelBatches, 5);
      expect(loaded.skipTranslationMemory, isFalse);
    });

    test('async load reads persisted values from prefs', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kUnitsKey: 25,
        kParallelKey: 8,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loaded =
          await container.read(translationSettingsProvider.notifier).ensureLoaded();

      expect(loaded.unitsPerBatch, 25);
      expect(loaded.parallelBatches, 8);
      // skipTranslationMemory is never persisted; always false on load.
      expect(loaded.skipTranslationMemory, isFalse);
    });

    test('async load clamps a too-high parallelBatches down to 20', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kParallelKey: 999,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loaded =
          await container.read(translationSettingsProvider.notifier).ensureLoaded();

      expect(loaded.parallelBatches, 20);
    });

    test('async load clamps a too-low parallelBatches up to 1', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kParallelKey: 0,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final loaded =
          await container.read(translationSettingsProvider.notifier).ensureLoaded();

      expect(loaded.parallelBatches, 1);
    });

    test('async load mutates provider state observed via read', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kUnitsKey: 42,
        kParallelKey: 3,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(translationSettingsProvider.notifier).ensureLoaded();

      final state = container.read(translationSettingsProvider);
      expect(state.unitsPerBatch, 42);
      expect(state.parallelBatches, 3);
    });
  });

  group('ensureLoaded()', () {
    test('loads once and returns current state on subsequent calls', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kUnitsKey: 10,
        kParallelKey: 4,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      final first = await notifier.ensureLoaded();
      final second = await notifier.ensureLoaded();

      expect(first.unitsPerBatch, 10);
      expect(second.unitsPerBatch, 10);
      expect(second.parallelBatches, 4);
    });

    test('returns the live state including session-only skip flag', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      notifier.setSkipTranslationMemory(true);

      final reloaded = await notifier.ensureLoaded();
      // _isLoaded is already true, so ensureLoaded does NOT reload from prefs
      // and the session-only skip flag survives.
      expect(reloaded.skipTranslationMemory, isTrue);
    });
  });

  group('updateSettings()', () {
    test('persists both keys to prefs', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      await notifier.updateSettings(unitsPerBatch: 15, parallelBatches: 7);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kUnitsKey), 15);
      expect(prefs.getInt(kParallelKey), 7);
    });

    test('updates provider state', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      await notifier.updateSettings(unitsPerBatch: 15, parallelBatches: 7);

      final state = container.read(translationSettingsProvider);
      expect(state.unitsPerBatch, 15);
      expect(state.parallelBatches, 7);
    });

    test('clamps parallelBatches above 20 before persisting and in state',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      await notifier.updateSettings(unitsPerBatch: 5, parallelBatches: 50);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kParallelKey), 20);
      expect(container.read(translationSettingsProvider).parallelBatches, 20);
    });

    test('clamps parallelBatches below 1 before persisting and in state',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      await notifier.updateSettings(unitsPerBatch: 5, parallelBatches: -3);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(kParallelKey), 1);
      expect(container.read(translationSettingsProvider).parallelBatches, 1);
    });

    test('does NOT clamp unitsPerBatch (0 = auto is preserved)', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      await notifier.updateSettings(unitsPerBatch: 0, parallelBatches: 5);

      final state = container.read(translationSettingsProvider);
      expect(state.unitsPerBatch, 0);
      expect(state.isAutoMode, isTrue);
    });

    test('preserves the session-only skip flag across an update', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      // Drain build()'s fire-and-forget _loadSettings() microtask before setting
      // the session flag, otherwise that late load resets skip=false during
      // updateSettings()'s await and clobbers the session value.
      await pumpEventQueue();
      notifier.setSkipTranslationMemory(true);

      await notifier.updateSettings(unitsPerBatch: 9, parallelBatches: 6);

      expect(
        container.read(translationSettingsProvider).skipTranslationMemory,
        isTrue,
      );
    });
  });

  group('setSkipTranslationMemory()', () {
    test('toggles the flag on while preserving other fields', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kUnitsKey: 12,
        kParallelKey: 6,
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      await notifier.ensureLoaded();
      notifier.setSkipTranslationMemory(true);

      final state = container.read(translationSettingsProvider);
      expect(state.skipTranslationMemory, isTrue);
      expect(state.unitsPerBatch, 12);
      expect(state.parallelBatches, 6);
    });

    test('toggles the flag back off', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final notifier = container.read(translationSettingsProvider.notifier);
      notifier.setSkipTranslationMemory(true);
      expect(
        container.read(translationSettingsProvider).skipTranslationMemory,
        isTrue,
      );

      notifier.setSkipTranslationMemory(false);
      expect(
        container.read(translationSettingsProvider).skipTranslationMemory,
        isFalse,
      );
    });

    test('is session-only and does not write to prefs', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container
          .read(translationSettingsProvider.notifier)
          .setSkipTranslationMemory(true);

      final prefs = await SharedPreferences.getInstance();
      // No skip key is ever persisted.
      expect(prefs.getKeys(), isEmpty);
    });
  });
}
