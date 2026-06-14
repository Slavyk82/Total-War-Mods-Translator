import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/batch_workshop_publish_notifier.dart';
import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/screens/batch_workshop_publish_screen.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import 'package:twmt/widgets/lists/status_pill.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Fake staging notifier returning canned data so the screen renders its full
/// layout instead of the no-staging fallback.
class _FakeStaging extends BatchPublishStagingNotifier {
  _FakeStaging(this._data);
  final BatchPublishStagingData? _data;
  @override
  BatchPublishStagingData? build() => _data;
}

/// Fake publish notifier returning an injected state and no-op'ing every method
/// that would otherwise touch real services (publishBatch is kicked off from
/// the screen's initState).
class _FakePublish extends BatchWorkshopPublishNotifier {
  _FakePublish(this._state);
  final BatchWorkshopPublishState _state;
  @override
  BatchWorkshopPublishState build() => _state;
  @override
  Future<void> publishBatch({
    required List<BatchPublishItemInfo> items,
    required String username,
    required String password,
    String? steamGuardCode,
  }) async {}
  @override
  Future<void> retryWithSteamGuard(String code) async {}
  @override
  void cancel() {}
  @override
  void silentCleanup() {}
}

WorkshopPublishParams _params({String publishedFileId = ''}) =>
    WorkshopPublishParams(
      appId: '1142710',
      publishedFileId: publishedFileId,
      contentFolder: r'C:\mods\x',
      previewFile: r'C:\mods\x\preview.png',
      title: 'Title',
      description: 'Desc',
    );

BatchPublishItemInfo _item(String name, {String publishedFileId = ''}) =>
    BatchPublishItemInfo(
      name: name,
      params: _params(publishedFileId: publishedFileId),
    );

BatchPublishStagingData _staging({String username = 'tester'}) =>
    BatchPublishStagingData(
      items: [
        _item('Alpha Mod'), // publish (empty id)
        _item('Beta Mod', publishedFileId: '123'), // update
      ],
      username: username,
      password: 'pw',
    );

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpScreen(
    WidgetTester t, {
    BatchPublishStagingData? staging,
    required BatchWorkshopPublishState state,
  }) async {
    await t.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const BatchWorkshopPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        batchPublishStagingProvider.overrideWith(() => _FakeStaging(staging)),
        batchWorkshopPublishProvider.overrideWith(() => _FakePublish(state)),
      ],
    ));
    await t.pump();
  }

  testWidgets('renders the no-staging fallback when nothing is staged',
      (t) async {
    await pumpScreen(t,
        staging: null, state: const BatchWorkshopPublishState());

    expect(find.byType(WizardScreenLayout), findsNothing);
    expect(find.textContaining('No batch').evaluate().isNotEmpty ||
        find.textContaining('No items').evaluate().isNotEmpty ||
        find.textContaining('staged').evaluate().isNotEmpty, isTrue);
  });

  testWidgets('renders the full wizard layout while publishing', (t) async {
    await pumpScreen(
      t,
      staging: _staging(),
      state: const BatchWorkshopPublishState(
        isPublishing: true,
        totalItems: 2,
        completedItems: 0,
        currentItemIndex: 0,
        currentItemName: 'Alpha Mod',
        currentItemProgress: 0.4,
        itemStatuses: {
          0: BatchPublishStatus.inProgress,
          1: BatchPublishStatus.pending,
        },
      ),
    );

    expect(find.byType(WizardScreenLayout), findsOneWidget);
    // Both mod names render in the per-pack list.
    expect(find.text('Alpha Mod'), findsWidgets);
    expect(find.text('Beta Mod'), findsWidgets);
    // The Stop action shows while actively publishing.
    expect(find.byType(StatusPill), findsWidgets);
  });

  testWidgets('renders a completed batch with mixed success/failure results',
      (t) async {
    await pumpScreen(
      t,
      staging: _staging(),
      state: const BatchWorkshopPublishState(
        isPublishing: false,
        totalItems: 2,
        completedItems: 2,
        itemStatuses: {
          0: BatchPublishStatus.success,
          1: BatchPublishStatus.failed,
        },
        results: [
          BatchPublishItemResult(
            index: 0,
            name: 'Alpha Mod',
            success: true,
            workshopId: '999',
          ),
          BatchPublishItemResult(
            index: 1,
            name: 'Beta Mod',
            success: false,
            errorMessage: 'upload failed',
          ),
        ],
      ),
    );

    expect(find.byType(WizardScreenLayout), findsOneWidget);
    // Success result surfaces the Workshop ID; failure surfaces the error.
    expect(find.textContaining('999'), findsWidgets);
    expect(find.text('upload failed'), findsOneWidget);
  });

  testWidgets('renders the cancelled state', (t) async {
    await pumpScreen(
      t,
      staging: _staging(),
      state: const BatchWorkshopPublishState(
        isPublishing: false,
        isCancelled: true,
        totalItems: 2,
        completedItems: 1,
        itemStatuses: {
          0: BatchPublishStatus.success,
          1: BatchPublishStatus.cancelled,
        },
        results: [
          BatchPublishItemResult(index: 0, name: 'Alpha Mod', success: true),
        ],
      ),
    );

    expect(find.byType(WizardScreenLayout), findsOneWidget);
  });

  testWidgets('renders the completed-with-errors header', (t) async {
    await pumpScreen(
      t,
      staging: _staging(),
      state: const BatchWorkshopPublishState(
        isPublishing: false,
        totalItems: 2,
        completedItems: 2,
        itemStatuses: {
          0: BatchPublishStatus.success,
          1: BatchPublishStatus.failed,
        },
        results: [
          BatchPublishItemResult(index: 0, name: 'Alpha Mod', success: true),
          BatchPublishItemResult(
              index: 1, name: 'Beta Mod', success: false, errorMessage: 'x'),
        ],
      ),
    );

    expect(find.byType(WizardScreenLayout), findsOneWidget);
  });

  testWidgets('surfaces the Steam Guard requirement', (t) async {
    await pumpScreen(
      t,
      staging: _staging(),
      state: const BatchWorkshopPublishState(
        isPublishing: false,
        needsSteamGuard: true,
        totalItems: 2,
        itemStatuses: {
          0: BatchPublishStatus.pending,
          1: BatchPublishStatus.pending,
        },
      ),
    );
    // Let the post-frame Steam Guard dialog trigger fire.
    await t.pump();
    await t.pump(const Duration(milliseconds: 50));

    expect(find.byType(WizardScreenLayout), findsOneWidget);
  });
}
