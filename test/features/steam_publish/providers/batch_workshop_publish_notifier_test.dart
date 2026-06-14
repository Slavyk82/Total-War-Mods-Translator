import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/steam_publish/providers/batch_workshop_publish_notifier.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';
import 'package:twmt/repositories/project_publication_repository.dart';
import 'package:twmt/services/steam/i_workshop_publish_service.dart';
import 'package:twmt/services/steam/models/steam_exceptions.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/services/steam/models/workshop_publish_result.dart';

import '../../../helpers/fakes/fake_logger.dart';

// Regression tests for BatchWorkshopPublishNotifier._saveWorkshopId.
//
// The repositories return Result and never throw, so failures from
// setPublication must be surfaced on the item's batch result as
// 'published but the Workshop ID could not be saved', while the upload
// itself stays successful.

class _MockPublishService extends Mock implements IWorkshopPublishService {}

class _MockPublicationRepository extends Mock
    implements ProjectPublicationRepository {}

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

void main() {
  setUpAll(() {
    registerFallbackValue(_params());
  });

  late _MockPublishService service;
  late _MockPublicationRepository pubRepo;
  late ProviderContainer container;

  setUp(() {
    service = _MockPublishService();
    pubRepo = _MockPublicationRepository();

    container = ProviderContainer(overrides: [
      workshopPublishServiceProvider.overrideWithValue(service),
      projectPublicationRepositoryProvider.overrideWithValue(pubRepo),
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

  Future<BatchWorkshopPublishState> runBatch({String? languageCode}) async {
    final notifier = container.read(batchWorkshopPublishProvider.notifier);
    await notifier.publishBatch(
      items: [
        BatchPublishItemInfo(
          name: 'Test Mod',
          params: _params(),
          projectId: 'p1',
          languageCode: languageCode,
        ),
      ],
      username: 'user',
      password: 'pw',
      steamGuardCode: '12345',
    );
    return container.read(batchWorkshopPublishProvider);
  }

  test(
      'successful upload whose setPublication returns Err surfaces '
      '"Workshop ID could not be saved" on the item result', () async {
    stubSuccessfulUpload('555000111');
    when(() => pubRepo.setPublication(
          any(),
          any(),
          any(),
          any(),
        )).thenAnswer((_) async => Err(TWMTDatabaseException('disk I/O error')));

    final state = await runBatch(languageCode: 'fr');

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
      'successful upload with a successful setPublication keeps a clean item '
      'result (no spurious save-failure message)', () async {
    stubSuccessfulUpload('555000333');
    when(() => pubRepo.setPublication(
          any(),
          any(),
          any(),
          any(),
        )).thenAnswer((_) async => Ok(null));

    final state = await runBatch(languageCode: 'fr');

    final result = state.results.single;
    expect(result.success, isTrue);
    expect(result.errorMessage, isNull);

    // Verify setPublication was called with the correct project id, language
    // code, workshop id and a non-zero timestamp.
    final captured = verify(() => pubRepo.setPublication(
          captureAny(),
          captureAny(),
          captureAny(),
          captureAny(),
        )).captured;
    expect(captured[0], 'p1');
    expect(captured[1], 'fr');
    expect(captured[2], '555000333');
    expect(captured[3], isA<int>().having((v) => v, 'timestamp', greaterThan(0)));
  });

  test('languageCode falls back to "fr" when null', () async {
    stubSuccessfulUpload('555000444');
    when(() => pubRepo.setPublication(
          any(),
          any(),
          any(),
          any(),
        )).thenAnswer((_) async => Ok(null));

    // Pass no languageCode (null) — should default to 'fr'
    await runBatch();

    final captured = verify(() => pubRepo.setPublication(
          captureAny(),
          captureAny(),
          captureAny(),
          captureAny(),
        )).captured;
    expect(captured[1], 'fr',
        reason: 'null languageCode must fall back to the default "fr"');
  });

  // Audit finding F15: statuses used to be keyed by the item's display name
  // (`statuses[item.name] = ...`), so two batch items with the same name
  // overwrote each other's status — the screen then showed the same (last
  // written) status for both rows. Statuses must be keyed by the item's
  // batch index, which is unique by construction.
  group('duplicate display names', () {
    /// Stubs the service so item 0 fails and item 1 succeeds.
    void stubFirstFailsSecondSucceeds(String workshopId) {
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
        onItemComplete?.call(
            0,
            Err(const SteamServiceException(
              'Timeout: file upload took too long',
              code: 'TIMEOUT',
            )));
        onItemComplete?.call(1, Ok(_publishResult(workshopId)));
      });
    }

    Future<BatchWorkshopPublishState> runBatchWithDuplicateNames() async {
      final notifier = container.read(batchWorkshopPublishProvider.notifier);
      await notifier.publishBatch(
        items: [
          BatchPublishItemInfo(
            name: 'Same Display Name',
            params: _params(),
            projectId: 'p1',
            languageCode: 'fr',
          ),
          BatchPublishItemInfo(
            name: 'Same Display Name',
            params: _params(),
            projectId: 'p2',
            languageCode: 'fr',
          ),
        ],
        username: 'user',
        password: 'pw',
        steamGuardCode: '12345',
      );
      return container.read(batchWorkshopPublishProvider);
    }

    test(
        'two items with the same name keep independent statuses '
        '(first failed, second success)', () async {
      stubFirstFailsSecondSucceeds('555000555');
      when(() => pubRepo.setPublication(
            any(),
            any(),
            any(),
            any(),
          )).thenAnswer((_) async => Ok(null));

      final state = await runBatchWithDuplicateNames();

      expect(state.itemStatuses, hasLength(2),
          reason: 'each batch item must keep its own status entry even when '
              'display names collide — name-keyed statuses overwrite each '
              'other');
      expect(
        state.itemStatuses.values,
        containsAll([BatchPublishStatus.failed, BatchPublishStatus.success]),
        reason: 'the failed first item must not be masked by the successful '
            'second item of the same name',
      );
      expect(state.itemStatuses[0], BatchPublishStatus.failed);
      expect(state.itemStatuses[1], BatchPublishStatus.success);

      // Results carry the batch index so the screen can look up each row's
      // own result instead of firstWhere-by-name returning the same result
      // for both rows.
      expect(state.results, hasLength(2));
      final first = state.results.singleWhere((r) => r.index == 0);
      final second = state.results.singleWhere((r) => r.index == 1);
      expect(first.success, isFalse);
      expect(first.errorMessage, contains('Timeout'));
      expect(second.success, isTrue);
      expect(second.workshopId, '555000555');
    });
  });
}
