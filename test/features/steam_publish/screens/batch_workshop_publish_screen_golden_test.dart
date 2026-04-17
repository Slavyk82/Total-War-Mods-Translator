import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/batch_workshop_publish_notifier.dart';
import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/screens/batch_workshop_publish_screen.dart';
import 'package:twmt/services/steam/models/workshop_publish_params.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Three-item batch fixture: FR translation project (update), DE translation
/// project (update), a multilingual compilation (publish).
BatchPublishStagingData _makeStaging() {
  WorkshopPublishParams params({required String publishedFileId}) =>
      WorkshopPublishParams(
        appId: '1142710',
        publishedFileId: publishedFileId,
        contentFolder: r'C:\fixtures\packs',
        previewFile: r'C:\fixtures\packs\preview.png',
        title: 'preview',
        description: 'preview',
      );
  return BatchPublishStagingData(
    items: [
      BatchPublishItemInfo(
        name: 'French Translation - Warhammer III',
        params: params(publishedFileId: '2987654321'),
        projectId: 'proj-1',
      ),
      BatchPublishItemInfo(
        name: 'German Translation - Warhammer III',
        params: params(publishedFileId: '2987654322'),
        projectId: 'proj-2',
      ),
      BatchPublishItemInfo(
        name: 'Multilingual Pack (fr/de/it)',
        params: params(publishedFileId: '0'),
        compilationId: 'comp-1',
      ),
    ],
    username: 'tester',
    password: '',
    steamGuardCode: null,
  );
}

/// Test-only staging notifier that returns a preloaded batch fixture.
class _StagedBatchNotifier extends BatchPublishStagingNotifier {
  _StagedBatchNotifier(this.fixture);
  final BatchPublishStagingData fixture;

  @override
  BatchPublishStagingData? build() => fixture;
}

/// Test-only batch publish notifier that exposes an in-progress state (2
/// completed + 1 uploading at 40%) without kicking off a real steamcmd
/// run.
class _InProgressBatchNotifier extends BatchWorkshopPublishNotifier {
  _InProgressBatchNotifier(this.seed);
  final BatchWorkshopPublishState seed;

  @override
  BatchWorkshopPublishState build() => seed;
}

BatchWorkshopPublishState _makeInProgressState() {
  return BatchWorkshopPublishState(
    isPublishing: true,
    totalItems: 3,
    completedItems: 2,
    currentItemName: 'Multilingual Pack (fr/de/it)',
    currentItemProgress: 0.4,
    itemStatuses: const {
      'French Translation - Warhammer III': BatchPublishStatus.success,
      'German Translation - Warhammer III': BatchPublishStatus.success,
      'Multilingual Pack (fr/de/it)': BatchPublishStatus.inProgress,
    },
    results: const [
      BatchPublishItemResult(
        name: 'French Translation - Warhammer III',
        success: true,
        workshopId: '2987654321',
      ),
      BatchPublishItemResult(
        name: 'German Translation - Warhammer III',
        success: true,
        workshopId: '2987654322',
      ),
    ],
  );
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final staging = _makeStaging();
    final seedState = _makeInProgressState();

    await t.pumpWidget(createThemedTestableWidget(
      const BatchWorkshopPublishScreen(),
      theme: theme,
      overrides: <Override>[
        batchPublishStagingProvider.overrideWith(
          () => _StagedBatchNotifier(staging),
        ),
        batchWorkshopPublishProvider.overrideWith(
          () => _InProgressBatchNotifier(seedState),
        ),
      ],
    ));
    await t.pump();
    // Let the post-frame callbacks settle without waiting on the real
    // publishBatch call — the overridden notifier short-circuits it.
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('batch publish atelier in-progress', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(BatchWorkshopPublishScreen),
      matchesGoldenFile('../goldens/batch_workshop_publish_atelier.png'),
    );
  });

  testWidgets('batch publish forge in-progress', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(BatchWorkshopPublishScreen),
      matchesGoldenFile('../goldens/batch_workshop_publish_forge.png'),
    );
  });
}
