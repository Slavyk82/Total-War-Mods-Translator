import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/settings/providers/maintenance_providers.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/mod_update_analysis_cache_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/translation_memory/i_translation_memory_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for MaintenanceStateNotifier (autoDispose).
//
// reanalyzeAllTranslations / clearStaleAnalysisCache used to write `state`
// after long awaits without checking `ref.mounted`. The provider's only
// watcher is the Maintenance section on the General settings tab; switching
// tabs mid-operation disposes the provider and the next state write (or the
// catch block's state write) threw UnmountedRefException, which escaped the
// fire-and-forget call site as an unhandled async error. The underlying DB
// work must still run to completion — only the state writes are guarded.

class _MockTranslationVersionRepository extends Mock
    implements TranslationVersionRepository {}

class _MockAnalysisCacheRepository extends Mock
    implements ModUpdateAnalysisCacheRepository {}

void main() {
  late _MockTranslationVersionRepository versionRepo;
  late _MockAnalysisCacheRepository cacheRepo;
  late ProviderContainer container;

  setUp(() {
    versionRepo = _MockTranslationVersionRepository();
    cacheRepo = _MockAnalysisCacheRepository();

    container = ProviderContainer(overrides: [
      translationVersionRepositoryProvider.overrideWithValue(versionRepo),
      modUpdateAnalysisCacheRepositoryProvider.overrideWithValue(cacheRepo),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ]);
    addTearDown(container.dispose);
  });

  group('reanalyzeAllTranslations', () {
    test('updates state with success result while watched', () async {
      when(() => versionRepo.countInconsistentStatuses()).thenAnswer(
        (_) async => const Ok((pendingWithText: 1, nonPendingWithoutText: 2)),
      );
      when(() => versionRepo.reanalyzeAllStatuses()).thenAnswer(
        (_) async =>
            const Ok((fixedToPending: 1, fixedToTranslated: 2, total: 10)),
      );

      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(maintenanceStateProvider.notifier);

      await notifier.reanalyzeAllTranslations();

      final state = container.read(maintenanceStateProvider);
      expect(state.isReanalyzing, isFalse);
      expect(state.lastResult, isNotNull);
      expect(state.lastResult!.success, isTrue);
      expect(state.lastResult!.fixedToPending, 1);
      expect(state.lastResult!.fixedToTranslated, 2);
    });

    test(
        'completes without UnmountedRefException when the provider is '
        'disposed mid-operation, and still runs the work to completion',
        () async {
      final reanalysisStarted = Completer<void>();
      final releaseReanalysis = Completer<void>();
      var reanalysisCompleted = false;

      when(() => versionRepo.countInconsistentStatuses()).thenAnswer(
        (_) async => const Ok((pendingWithText: 1, nonPendingWithoutText: 2)),
      );
      when(() => versionRepo.reanalyzeAllStatuses()).thenAnswer((_) async {
        reanalysisStarted.complete();
        await releaseReanalysis.future;
        reanalysisCompleted = true;
        return const Ok((fixedToPending: 1, fixedToTranslated: 2, total: 10));
      });

      // The Maintenance section watching the provider.
      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      final notifier = container.read(maintenanceStateProvider.notifier);

      // Fire-and-forget, exactly like the production call site
      // (maintenance_section.dart). Captured only to assert it doesn't throw.
      final operation = notifier.reanalyzeAllTranslations();

      await reanalysisStarted.future;

      // User switches settings tab: the section unmounts, removing the last
      // listener of this autoDispose provider.
      subscription.close();
      await container.pump();

      releaseReanalysis.complete();

      // Must complete without an UnmountedRefException.
      await operation;

      expect(reanalysisCompleted, isTrue,
          reason: 'the DB reanalysis itself must not be abandoned');
    });

    test(
        'error path is dispose-safe: a repository failure after dispose '
        'does not rethrow from the catch block', () async {
      final countStarted = Completer<void>();
      final releaseCount = Completer<void>();

      when(() => versionRepo.countInconsistentStatuses())
          .thenAnswer((_) async {
        countStarted.complete();
        await releaseCount.future;
        throw Exception('database is locked');
      });

      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      final notifier = container.read(maintenanceStateProvider.notifier);

      final operation = notifier.reanalyzeAllTranslations();

      await countStarted.future;
      subscription.close();
      await container.pump();
      releaseCount.complete();

      // The catch block must log and bail out instead of writing state on a
      // disposed ref (which would rethrow UnmountedRefException).
      await operation;
    });

    test('reports error in state when repository fails while watched',
        () async {
      when(() => versionRepo.countInconsistentStatuses())
          .thenAnswer((_) async => throw Exception('boom'));

      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(maintenanceStateProvider.notifier);

      await notifier.reanalyzeAllTranslations();

      final state = container.read(maintenanceStateProvider);
      expect(state.isReanalyzing, isFalse);
      expect(state.lastResult!.success, isFalse);
      expect(state.lastResult!.message, contains('boom'));
    });
  });

  group('clearStaleAnalysisCache', () {
    test('updates state with success result while watched', () async {
      when(() => cacheRepo.deleteAllWithChanges())
          .thenAnswer((_) async => const Ok(5));

      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      addTearDown(subscription.close);
      final notifier = container.read(maintenanceStateProvider.notifier);

      await notifier.clearStaleAnalysisCache();

      final state = container.read(maintenanceStateProvider);
      expect(state.isReanalyzing, isFalse);
      expect(state.lastResult!.success, isTrue);
      expect(state.lastResult!.message, contains('5'));
    });

    test(
        'completes without UnmountedRefException when the provider is '
        'disposed mid-operation, and still runs the work to completion',
        () async {
      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();
      var deleteCompleted = false;

      when(() => cacheRepo.deleteAllWithChanges()).thenAnswer((_) async {
        deleteStarted.complete();
        await releaseDelete.future;
        deleteCompleted = true;
        return const Ok(5);
      });

      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      final notifier = container.read(maintenanceStateProvider.notifier);

      final operation = notifier.clearStaleAnalysisCache();

      await deleteStarted.future;
      subscription.close();
      await container.pump();
      releaseDelete.complete();

      await operation;

      expect(deleteCompleted, isTrue,
          reason: 'the cache cleanup itself must not be abandoned');
    });

    test(
        'error path is dispose-safe: a repository failure after dispose '
        'does not rethrow from the catch block', () async {
      final deleteStarted = Completer<void>();
      final releaseDelete = Completer<void>();

      when(() => cacheRepo.deleteAllWithChanges()).thenAnswer((_) async {
        deleteStarted.complete();
        await releaseDelete.future;
        throw Exception('database is locked');
      });

      final subscription =
          container.listen(maintenanceStateProvider, (_, _) {});
      final notifier = container.read(maintenanceStateProvider.notifier);

      final operation = notifier.clearStaleAnalysisCache();

      await deleteStarted.future;
      subscription.close();
      await container.pump();
      releaseDelete.complete();

      await operation;
    });
  });

  group('rebuildTranslationMemory / migrateLegacyHashes', () {
    test(
        'rebuildTranslationMemory catch path is dispose-safe (logging must '
        'not read a disposed ref)', () async {
      final tmService = _MockTranslationMemoryService();
      final rebuildStarted = Completer<void>();
      final releaseRebuild = Completer<void>();

      when(() => tmService.rebuildFromTranslations(
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async {
        rebuildStarted.complete();
        await releaseRebuild.future;
        throw Exception('database is locked');
      });

      final localContainer = ProviderContainer(overrides: [
        translationMemoryServiceProvider.overrideWithValue(tmService),
        loggingServiceProvider.overrideWithValue(FakeLogger()),
      ]);
      addTearDown(localContainer.dispose);

      final subscription =
          localContainer.listen(maintenanceStateProvider, (_, _) {});
      final notifier = localContainer.read(maintenanceStateProvider.notifier);

      final operation = notifier.rebuildTranslationMemory();

      await rebuildStarted.future;
      subscription.close();
      await localContainer.pump();
      releaseRebuild.complete();

      await operation;
    });
  });
}

class _MockTranslationMemoryService extends Mock
    implements ITranslationMemoryService {}
