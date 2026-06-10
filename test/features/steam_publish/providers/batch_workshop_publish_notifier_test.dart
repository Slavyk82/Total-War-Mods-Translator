import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/steam_publish/providers/batch_workshop_publish_notifier.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/project_repository.dart';
import 'package:twmt/services/steam/i_workshop_publish_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for BatchWorkshopPublishNotifier._saveWorkshopId.
//
// The repositories return Result and never throw, so the old code — which
// discarded the Results of projectRepo.getById/update and only logged inside
// dead catch blocks — silently lost DB write failures occurring AFTER a
// successful Steam upload. The refreshed list then showed the just-published
// item as unpublished, and republishing without the saved id creates a
// duplicate Workshop item. A failed save must surface on the item's batch
// result as 'published but the Workshop ID could not be saved', while the
// upload itself stays successful.

class _MockPublishService extends Mock implements IWorkshopPublishService {}

class _MockProjectRepository extends Mock implements ProjectRepository {}

WorkshopPublishParams _params() => const WorkshopPublishParams(
      appId: '1142710',
      publishedFileId: '',
      contentFolder: 'C:/content',
      previewFile: 'C:/content/mod.png',
      title: 'Test Mod',
      description: 'desc',
      changeNote: 'note',
    );

WorkshopPublishResult _publishResult(String workshopId) =>
    WorkshopPublishResult(
      workshopId: workshopId,
      wasUpdate: false,
      durationMs: 100,
      timestamp: DateTime(2026, 6, 10),
      rawOutput: '',
    );

Project _project(String id) => Project(
      id: id,
      name: 'P-$id',
      gameInstallationId: 'g',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  setUpAll(() {
    registerFallbackValue(_params());
    registerFallbackValue(_project('_'));
  });

  late _MockPublishService service;
  late _MockProjectRepository projectRepo;
  late ProviderContainer container;

  setUp(() {
    service = _MockPublishService();
    projectRepo = _MockProjectRepository();

    container = ProviderContainer(overrides: [
      workshopPublishServiceProvider.overrideWithValue(service),
      projectRepositoryProvider.overrideWithValue(projectRepo),
      loggingServiceProvider.overrideWithValue(FakeLogger()),
    ]);
    addTearDown(container.dispose);
  });

  /// Stubs the service so the single batch item uploads successfully with
  /// Workshop id [workshopId].
  void stubSuccessfulUpload(String workshopId) {
    when(() => service.publishBatch(
          items: any(named: 'items'),
          username: any(named: 'username'),
          password: any(named: 'password'),
          steamGuardCode: any(named: 'steamGuardCode'),
          onItemStart: any(named: 'onItemStart'),
          onItemProgress: any(named: 'onItemProgress'),
          onItemComplete: any(named: 'onItemComplete'),
        )).thenAnswer((invocation) async {
      final onItemComplete = invocation.namedArguments[#onItemComplete]
          as void Function(
              int, Result<WorkshopPublishResult, SteamServiceException>)?;
      onItemComplete?.call(0, Ok(_publishResult(workshopId)));
    });
  }

  Future<BatchWorkshopPublishState> runBatch() async {
    final notifier = container.read(batchWorkshopPublishProvider.notifier);
    await notifier.publishBatch(
      items: [
        BatchPublishItemInfo(
          name: 'Test Mod',
          params: _params(),
          projectId: 'p1',
        ),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );
    return container.read(batchWorkshopPublishProvider);
  }

  test(
      'successful upload whose projectRepo.update returns Err surfaces '
      '"Workshop ID could not be saved" on the item result', () async {
    stubSuccessfulUpload('555000111');
    when(() => projectRepo.getById('p1'))
        .thenAnswer((_) async => Ok(_project('p1')));
    when(() => projectRepo.update(any())).thenAnswer(
        (_) async => Err(TWMTDatabaseException('disk I/O error')));

    final state = await runBatch();

    expect(state.results, hasLength(1));
    final result = state.results.single;
    expect(result.success, isTrue,
        reason: 'the Steam upload itself succeeded — the item must not be '
            'reported as a failed upload');
    expect(result.workshopId, '555000111');
    expect(result.errorMessage, isNotNull,
        reason: 'a Result-level DB write failure after a successful upload '
            'must not pass silently — republishing without the saved id '
            'creates a duplicate Workshop item');
    expect(result.errorMessage, contains('could not be saved'));
    expect(result.errorMessage, contains('disk I/O error'));
  });

  test(
      'successful upload whose projectRepo.getById returns Err surfaces the '
      'load failure on the item result instead of silently skipping the save',
      () async {
    stubSuccessfulUpload('555000222');
    when(() => projectRepo.getById('p1')).thenAnswer(
        (_) async => Err(TWMTDatabaseException('Project not found')));

    final state = await runBatch();

    final result = state.results.single;
    expect(result.success, isTrue);
    expect(result.errorMessage, isNotNull,
        reason: 'a getById Err means the Workshop ID was never written — '
            'the old code skipped the write with no log and no message');
    expect(result.errorMessage, contains('could not be saved'));
    expect(result.errorMessage, contains('could not load project'));
    verifyNever(() => projectRepo.update(any()));
  });

  test(
      'successful upload with a successful save keeps a clean item result '
      '(no spurious save-failure message)', () async {
    stubSuccessfulUpload('555000333');
    when(() => projectRepo.getById('p1'))
        .thenAnswer((_) async => Ok(_project('p1')));
    when(() => projectRepo.update(any())).thenAnswer((invocation) async =>
        Ok(invocation.positionalArguments.first as Project));

    final state = await runBatch();

    final result = state.results.single;
    expect(result.success, isTrue);
    expect(result.errorMessage, isNull);

    // The persisted project must carry the new Workshop id.
    final updated =
        verify(() => projectRepo.update(captureAny())).captured.single
            as Project;
    expect(updated.publishedSteamId, '555000333');
    expect(updated.publishedAt, isNotNull);
  });
}
