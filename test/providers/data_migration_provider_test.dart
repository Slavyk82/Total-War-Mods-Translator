// Unit tests for lib/providers/data_migration_provider.dart.
//
// DataMigration is a @riverpod class notifier that runs one-time TM
// migrations (rebuild + legacy-hash migration), tracking progress in
// DataMigrationState and persisting per-step completion flags in
// SharedPreferences. This is a sensitive path (data migration) that
// previously had zero coverage.
//
// These tests drive the REAL notifier through a ProviderContainer with the
// TranslationMemory service mocked (mocktail) and SharedPreferences faked
// (setMockInitialValues) so the production DB / real app-data dir is never
// touched. They cover: state model math (progressPercent, copyWith),
// needsMigration gating, the happy path (idle -> running -> complete),
// progress-message formatting for both steps, the failure paths (service
// returns Err and service throws -> error state, never an unhandled
// exception), the re-entry guard, the already-complete short-circuit, and
// retry-after-failure clearing the error.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/data_migration_provider.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';
import 'package:twmt/services/translation_memory/models/tm_exceptions.dart';

import '../helpers/fakes/fake_logger.dart';

class _MockTmService extends Mock implements ITranslationMemoryService {}

// SharedPreferences keys the provider persists per-step completion under.
const _rebuildKey = 'tm_rebuild_v1_completed';
const _hashKey = 'tm_hash_migration_v1_completed';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DataMigrationState (pure)', () {
    test('defaults describe an idle, not-started migration', () {
      const s = DataMigrationState();
      expect(s.isRunning, isFalse);
      expect(s.isComplete, isFalse);
      expect(s.currentStep, isEmpty);
      expect(s.progressMessage, isEmpty);
      expect(s.currentProgress, 0);
      expect(s.totalProgress, 0);
      expect(s.error, isNull);
    });

    test('progressPercent is 0 when totalProgress is 0 (guards divide-by-0)',
        () {
      const s = DataMigrationState(currentProgress: 5, totalProgress: 0);
      expect(s.progressPercent, 0.0);
    });

    test('progressPercent is the ratio currentProgress / totalProgress', () {
      const s = DataMigrationState(currentProgress: 50, totalProgress: 200);
      expect(s.progressPercent, closeTo(0.25, 1e-9));
    });

    test('progressPercent clamps to 1.0 when current exceeds total', () {
      const s = DataMigrationState(currentProgress: 300, totalProgress: 200);
      expect(s.progressPercent, 1.0);
    });

    test('copyWith preserves unspecified fields', () {
      const s = DataMigrationState(
        isRunning: true,
        currentStep: 'step',
        currentProgress: 3,
        totalProgress: 10,
      );
      final c = s.copyWith(progressMessage: 'msg');
      expect(c.isRunning, isTrue);
      expect(c.currentStep, 'step');
      expect(c.currentProgress, 3);
      expect(c.totalProgress, 10);
      expect(c.progressMessage, 'msg');
    });

    test(
        'copyWith resets error to null unless an error is explicitly passed '
        '(only the catch-block state carries an error)', () {
      const s = DataMigrationState(error: 'boom');
      // A copyWith that does not pass `error` clears it — this is how the
      // provider clears a stale error when a retry starts running.
      expect(s.copyWith(isRunning: true).error, isNull);
      // Explicitly passing an error keeps it.
      expect(s.copyWith(error: 'still bad').error, 'still bad');
    });
  });

  group('DataMigration notifier', () {
    late _MockTmService tm;
    late ProviderContainer container;

    ProviderContainer buildContainer() {
      final c = ProviderContainer(overrides: [
        translationMemoryServiceProvider.overrideWithValue(tm),
        loggingServiceProvider.overrideWithValue(FakeLogger()),
      ]);
      // Keep the autoDispose provider mounted for the whole test.
      final sub = c.listen(dataMigrationProvider, (_, _) {});
      addTearDown(sub.close);
      addTearDown(c.dispose);
      return c;
    }

    void stubMigrateOk({int processed = 0}) {
      when(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => Ok<int, TmServiceException>(processed),
      );
    }

    setUp(() {
      tm = _MockTmService();
    });

    group('needsMigration', () {
      test('true when neither step has been completed', () async {
        SharedPreferences.setMockInitialValues({});
        container = buildContainer();
        final notifier = container.read(dataMigrationProvider.notifier);
        expect(await notifier.needsMigration(), isTrue);
      });

      test('true when only the rebuild step is complete', () async {
        SharedPreferences.setMockInitialValues({_rebuildKey: true});
        container = buildContainer();
        final notifier = container.read(dataMigrationProvider.notifier);
        expect(await notifier.needsMigration(), isTrue);
      });

      test('true when only the hash-migration step is complete', () async {
        SharedPreferences.setMockInitialValues({_hashKey: true});
        container = buildContainer();
        final notifier = container.read(dataMigrationProvider.notifier);
        expect(await notifier.needsMigration(), isTrue);
      });

      test('false when both steps are complete', () async {
        SharedPreferences.setMockInitialValues({
          _rebuildKey: true,
          _hashKey: true,
        });
        container = buildContainer();
        final notifier = container.read(dataMigrationProvider.notifier);
        expect(await notifier.needsMigration(), isFalse);
      });
    });

    test('build() returns the idle initial state', () async {
      SharedPreferences.setMockInitialValues({});
      container = buildContainer();
      final state = container.read(dataMigrationProvider);
      expect(state.isRunning, isFalse);
      expect(state.isComplete, isFalse);
      expect(state.error, isNull);
    });

    test('happy path: both steps run, state completes, flags persisted',
        () async {
      SharedPreferences.setMockInitialValues({});
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => Ok<({int added, int existing}), TmServiceException>(
          (added: 5, existing: 3),
        ),
      );
      stubMigrateOk(processed: 7);

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      await notifier.runMigrations();

      final state = container.read(dataMigrationProvider);
      expect(state.isRunning, isFalse);
      expect(state.isComplete, isTrue);
      expect(state.error, isNull);
      expect(state.currentStep, 'Migration complete');
      expect(state.progressMessage, isEmpty);

      // Both services were invoked exactly once.
      verify(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).called(1);
      verify(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          )).called(1);

      // Completion flags were persisted so the migration will not re-run.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_rebuildKey), isTrue);
      expect(prefs.getBool(_hashKey), isTrue);
    });

    test(
        'rebuild progress callback formats the message and updates counts',
        () async {
      // Only the rebuild step runs (hash step already done).
      SharedPreferences.setMockInitialValues({_hashKey: true});
      container = buildContainer();

      DataMigrationState? progressSnapshot;
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((inv) async {
        final cb =
            inv.namedArguments[#onProgress] as void Function(int, int, int)?;
        cb?.call(50, 200, 3);
        // The provider updates `state` synchronously inside the callback, so
        // read it back deterministically here.
        progressSnapshot = container.read(dataMigrationProvider);
        return Ok<({int added, int existing}), TmServiceException>(
          (added: 3, existing: 197),
        );
      });

      final notifier = container.read(dataMigrationProvider.notifier);
      await notifier.runMigrations();

      expect(progressSnapshot, isNotNull);
      expect(progressSnapshot!.currentProgress, 50);
      expect(progressSnapshot!.totalProgress, 200);
      expect(progressSnapshot!.progressMessage, '50 / 200 translations (3 added)');
      expect(progressSnapshot!.currentStep, 'Rebuilding Translation Memory...');

      final state = container.read(dataMigrationProvider);
      expect(state.isComplete, isTrue);
      // The hash-migration step was skipped (its flag was already set).
      verifyNever(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          ));
    });

    test(
        'hash-migration progress callback formats the "entries" message',
        () async {
      // Only the hash step runs (rebuild already done).
      SharedPreferences.setMockInitialValues({_rebuildKey: true});
      container = buildContainer();

      DataMigrationState? progressSnapshot;
      when(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((inv) async {
        final cb = inv.namedArguments[#onProgress] as void Function(int, int)?;
        cb?.call(30, 40);
        progressSnapshot = container.read(dataMigrationProvider);
        return Ok<int, TmServiceException>(40);
      });

      final notifier = container.read(dataMigrationProvider.notifier);
      await notifier.runMigrations();

      expect(progressSnapshot, isNotNull);
      expect(progressSnapshot!.currentProgress, 30);
      expect(progressSnapshot!.totalProgress, 40);
      expect(progressSnapshot!.progressMessage, '30 / 40 entries');
      expect(progressSnapshot!.currentStep,
          'Migrating Translation Memory hashes...');

      // Rebuild step was skipped entirely.
      verifyNever(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          ));
      expect(container.read(dataMigrationProvider).isComplete, isTrue);
    });

    test('rebuild returns Err -> error state, no unhandled exception',
        () async {
      SharedPreferences.setMockInitialValues({});
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Err<({int added, int existing}), TmServiceException>(
          TmServiceException('rebuild exploded'),
        ),
      );

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      // Must complete normally (the notifier catches and records the error).
      await notifier.runMigrations();

      final state = container.read(dataMigrationProvider);
      expect(state.isRunning, isFalse);
      expect(state.isComplete, isFalse);
      expect(state.error, isNotNull);
      expect(state.error, contains('rebuild exploded'));

      // The second step must not run and the flag must not be persisted.
      verifyNever(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          ));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_rebuildKey), isNot(true));
    });

    test('rebuild throws -> error state carries the exception text', () async {
      SharedPreferences.setMockInitialValues({});
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => throw Exception('database is locked'));

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      await notifier.runMigrations();

      final state = container.read(dataMigrationProvider);
      expect(state.isRunning, isFalse);
      expect(state.isComplete, isFalse);
      expect(state.error, contains('database is locked'));
    });

    test('hash-migration returns Err -> error state (rebuild already done)',
        () async {
      SharedPreferences.setMockInitialValues({_rebuildKey: true});
      when(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Err<int, TmServiceException>(
          TmServiceException('hash migration failed'),
        ),
      );

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      await notifier.runMigrations();

      final state = container.read(dataMigrationProvider);
      expect(state.isComplete, isFalse);
      expect(state.error, contains('hash migration failed'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(_hashKey), isNot(true));
    });

    test('already complete: both flags set -> completes without calling TM',
        () async {
      SharedPreferences.setMockInitialValues({
        _rebuildKey: true,
        _hashKey: true,
      });

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      await notifier.runMigrations();

      final state = container.read(dataMigrationProvider);
      expect(state.isComplete, isTrue);
      expect(state.error, isNull);
      verifyNever(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          ));
      verifyNever(() => tm.migrateLegacyHashes(
            onProgress: any(named: 'onProgress'),
          ));
    });

    test('re-entry guard: a second concurrent call is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final gate = Completer<void>();
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async {
        await gate.future;
        return const Ok<({int added, int existing}), TmServiceException>(
          (added: 1, existing: 0),
        );
      });
      stubMigrateOk();

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      // First call starts and suspends on the gated rebuild.
      final first = notifier.runMigrations();
      // Second call while isRunning is true must return immediately.
      final second = notifier.runMigrations();

      gate.complete();
      await Future.wait([first, second]);

      // Despite two calls, the rebuild service ran exactly once.
      verify(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).called(1);
      expect(container.read(dataMigrationProvider).isComplete, isTrue);
    });

    test('retry after failure clears the error and completes', () async {
      SharedPreferences.setMockInitialValues({});
      // First attempt: rebuild fails.
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Err<({int added, int existing}), TmServiceException>(
          TmServiceException('transient failure'),
        ),
      );
      stubMigrateOk();

      container = buildContainer();
      final notifier = container.read(dataMigrationProvider.notifier);

      await notifier.runMigrations();
      expect(container.read(dataMigrationProvider).error,
          contains('transient failure'));

      // Second attempt: rebuild now succeeds.
      when(() => tm.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer(
        (_) async => const Ok<({int added, int existing}), TmServiceException>(
          (added: 2, existing: 1),
        ),
      );

      await notifier.runMigrations();

      final state = container.read(dataMigrationProvider);
      expect(state.error, isNull);
      expect(state.isComplete, isTrue);
    });
  });
}
