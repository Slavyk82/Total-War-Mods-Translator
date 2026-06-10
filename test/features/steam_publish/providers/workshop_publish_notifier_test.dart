import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/steam_publish/providers/workshop_publish_notifier.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/compilation_repository.dart';
import 'package:twmt/services/steam/i_workshop_publish_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for WorkshopPublishNotifier.silentCleanup().
//
// silentCleanup() is called from WorkshopPublishScreen.dispose() while an
// upload may still be in flight. It used to cancel the subscriptions and the
// steamcmd process but never set _silentlyCleaned = true (the batch notifier
// did), so when the cancelled `await service.publish(...)` resolved with Err,
// the continuation fell into the error branch and wrote phase=error onto the
// app-scoped provider — exactly the state write the method's doc comment
// ('Clean up without setting state') promises not to do, flashing a stale
// 'failed' view when the screen is reopened. After silentCleanup() the
// pending publish continuation must not write state at all.

class _MockPublishService extends Mock implements IWorkshopPublishService {}

class _MockCompilationRepository extends Mock
    implements CompilationRepository {}

WorkshopPublishParams _params() => const WorkshopPublishParams(
      appId: '1142710',
      publishedFileId: '1234567890',
      contentFolder: 'C:/content',
      previewFile: 'C:/content/mod.png',
      title: 'Test Mod',
      description: 'desc',
      changeNote: 'note',
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_params());
  });

  late _MockPublishService service;
  late StreamController<double> progressController;
  late StreamController<String> outputController;
  late ProviderContainer container;

  setUp(() {
    service = _MockPublishService();
    progressController = StreamController<double>.broadcast();
    outputController = StreamController<String>.broadcast();

    when(() => service.progressStream)
        .thenAnswer((_) => progressController.stream);
    when(() => service.outputStream)
        .thenAnswer((_) => outputController.stream);
    when(() => service.cancel()).thenAnswer((_) async {});

    container = ProviderContainer(overrides: [
      workshopPublishServiceProvider.overrideWithValue(service),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ]);
    addTearDown(container.dispose);
    addTearDown(progressController.close);
    addTearDown(outputController.close);
  });

  test(
      'silentCleanup() during an in-flight upload: the pending publish '
      'continuation must NOT write an error state', () async {
    final publishStarted = Completer<void>();
    final releasePublish =
        Completer<Result<WorkshopPublishResult, SteamServiceException>>();

    when(() => service.publish(
          params: any(named: 'params'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          steamGuardCode: any(named: 'steamGuardCode'),
        )).thenAnswer((_) {
      publishStarted.complete();
      return releasePublish.future;
    });

    final notifier = container.read(workshopPublishProvider.notifier);

    final publishFuture = notifier.publish(
      params: _params(),
      username: 'user',
      password: 'pw',
    );

    await publishStarted.future;
    expect(container.read(workshopPublishProvider).phase,
        PublishPhase.uploading);

    // Screen dispose() during the upload.
    notifier.silentCleanup();
    verify(() => service.cancel()).called(1);

    // The cancelled steamcmd run resolves the pending publish with Err
    // (PUBLISH_CANCELLED) — phase is still `uploading` because silentCleanup
    // deliberately writes no state, so only the _silentlyCleaned flag can
    // stop the continuation from writing phase=error.
    releasePublish.complete(Err(const WorkshopPublishException(
      'Publish operation was cancelled',
    )));
    await publishFuture;

    final state = container.read(workshopPublishProvider);
    expect(state.phase, isNot(PublishPhase.error),
        reason: 'silentCleanup() promises "clean up without setting state": '
            'the post-cleanup continuation must not persist a stale error '
            'on the app-scoped provider');
    expect(state.errorMessage, isNull);
  });

  test(
      'sanity (guard not over-broad): without silentCleanup() the same Err '
      'still surfaces as an error state', () async {
    when(() => service.publish(
          params: any(named: 'params'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          steamGuardCode: any(named: 'steamGuardCode'),
        )).thenAnswer((_) async => Err(const WorkshopPublishException(
          'Upload exploded',
        )));

    final notifier = container.read(workshopPublishProvider.notifier);
    await notifier.publish(
      params: _params(),
      username: 'user',
      password: 'pw',
    );

    final state = container.read(workshopPublishProvider);
    expect(state.phase, PublishPhase.error);
    expect(state.errorMessage, 'Upload exploded');
  });

  test(
      'silentCleanup() during an in-flight upload that SUCCEEDS: the Workshop '
      'ID is still persisted, but no completed state is written', () async {
    final compilationRepo = _MockCompilationRepository();
    when(() => compilationRepo.updateAfterPublish(any(), any(), any()))
        .thenAnswer((_) async => const Ok(null));

    final scoped = ProviderContainer(overrides: [
      workshopPublishServiceProvider.overrideWithValue(service),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
      compilationRepositoryProvider.overrideWithValue(compilationRepo),
    ]);
    addTearDown(scoped.dispose);

    final releasePublish =
        Completer<Result<WorkshopPublishResult, SteamServiceException>>();
    when(() => service.publish(
          params: any(named: 'params'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          steamGuardCode: any(named: 'steamGuardCode'),
        )).thenAnswer((_) => releasePublish.future);

    final notifier = scoped.read(workshopPublishProvider.notifier);
    final publishFuture = notifier.publish(
      params: _params(),
      username: 'user',
      password: 'pw',
      compilationId: 'comp-1',
    );

    // Screen dispose() while the upload is in flight...
    notifier.silentCleanup();
    // ...then steamcmd finishes successfully anyway.
    releasePublish.complete(Ok(WorkshopPublishResult(
      workshopId: '9999',
      wasUpdate: false,
      durationMs: 1000,
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      rawOutput: '',
    )));
    await publishFuture;

    // The id must be persisted (the provider is app-scoped, dropping the id
    // would orphan the published item and invite a duplicate republish)...
    verify(() => compilationRepo.updateAfterPublish('comp-1', '9999', any()))
        .called(1);
    // ...but the UI state must not be resurrected.
    final state = scoped.read(workshopPublishProvider);
    expect(state.phase, isNot(PublishPhase.completed),
        reason: 'silentCleanup() promises no state writes; only the DB '
            'side-effect may run');
  });

  test(
      'publish() after a previous silentCleanup() resets the flag: '
      'a fresh run reports its outcome normally', () async {
    // First run: cleaned up mid-flight.
    final firstRelease =
        Completer<Result<WorkshopPublishResult, SteamServiceException>>();
    when(() => service.publish(
          params: any(named: 'params'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          steamGuardCode: any(named: 'steamGuardCode'),
        )).thenAnswer((_) => firstRelease.future);

    final notifier = container.read(workshopPublishProvider.notifier);
    final firstRun = notifier.publish(
      params: _params(),
      username: 'user',
      password: 'pw',
    );
    notifier.silentCleanup();
    firstRelease.complete(
        Err(const WorkshopPublishException('cancelled')));
    await firstRun;

    // Second run: must not be muted by the stale flag.
    when(() => service.publish(
          params: any(named: 'params'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          steamGuardCode: any(named: 'steamGuardCode'),
        )).thenAnswer((_) async => Err(const WorkshopPublishException(
          'Second run failed',
        )));

    await notifier.publish(
      params: _params(),
      username: 'user',
      password: 'pw',
    );

    final state = container.read(workshopPublishProvider);
    expect(state.phase, PublishPhase.error);
    expect(state.errorMessage, 'Second run failed');
  });
}
