import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/providers/workshop_publish_notifier.dart';
import 'package:twmt/features/steam_publish/screens/workshop_publish_screen.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/wizard/wizard_screen_layout.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Drives the publish phase directly so the screen's timer management can be
/// exercised without running a real publish flow.
class _StubWorkshopPublishNotifier extends WorkshopPublishNotifier {
  void setPhase(PublishPhase phase) {
    state = WorkshopPublishState(phase: phase);
  }

  // The real implementation reads the publish service (unavailable in widget
  // tests) to cancel a running steamcmd process.
  @override
  void silentCleanup() {}
}

/// Stages a [PublishableItem] without going through the publishing list UI.
class _StubStagingNotifier extends SinglePublishStagingNotifier {
  _StubStagingNotifier(this._item);

  final PublishableItem? _item;

  @override
  PublishableItem? build() => _item;
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders WizardScreenLayout or no-staging fallback', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const WorkshopPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: const <Override>[],
    ));
    await t.pump();
    // The screen guards on staging data (a `PublishableItem` staged via
    // `singlePublishStagingProvider`). With no staged item, the screen
    // renders a DetailScreenToolbar + empty-state fallback; otherwise the
    // full WizardScreenLayout is rendered.
    expect(
      find.byType(WizardScreenLayout).evaluate().isNotEmpty ||
          find.textContaining('No pack').evaluate().isNotEmpty ||
          find.textContaining('No item').evaluate().isNotEmpty ||
          find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
      isTrue,
    );
  });

  testWidgets(
      'elapsed upload timer restarts from zero on a retried publish '
      'instead of showing the stale first-attempt start time', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    // Stage an updatable item: hasPack requires a real file on disk and a
    // non-empty publishedSteamId switches the screen into update mode.
    final tempDir = Directory.systemTemp.createTempSync('twmt_publish_screen_');
    addTearDown(() => tempDir.deleteSync(recursive: true));
    final packPath = p.join(tempDir.path, 'mypack.pack');
    File(packPath).writeAsStringSync('pack-data');

    final item = CompilationPublishItem(
      compilation: Compilation(
        id: 'comp-1',
        name: 'My Compilation',
        prefix: '!!_FR_',
        packName: 'mypack',
        gameInstallationId: 'game-1',
        lastOutputPath: packPath,
        lastGeneratedAt: 1700000000,
        publishedSteamId: '1234567890',
        publishedAt: 1700000001,
        createdAt: 1,
        updatedAt: 1,
      ),
      languageCode: 'fr',
      projectCount: 2,
      fileSize: 2048,
    );

    final publishNotifier = _StubWorkshopPublishNotifier();

    await t.pumpWidget(createThemedTestableWidget(
      const WorkshopPublishScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: <Override>[
        workshopPublishProvider.overrideWith(() => publishNotifier),
        singlePublishStagingProvider
            .overrideWith(() => _StubStagingNotifier(item)),
      ],
    ));
    // Flush initState's microtask reset.
    await t.pump();
    expect(find.byType(WizardScreenLayout), findsOneWidget);

    // First upload: elapsed label starts at 0s.
    publishNotifier.setPhase(PublishPhase.uploading);
    await t.pump();
    expect(find.text('0s'), findsOneWidget);

    // The upload fails.
    publishNotifier.setPhase(PublishPhase.error);
    await t.pump();

    // The user spends real wall-clock time on the error panel. The elapsed
    // label is computed from DateTime.now(), so this must be real time —
    // fake-async pump durations do not advance the wall clock.
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1300)),
    );

    // Retry: notifier resets to idle, then the user submits again.
    publishNotifier.setPhase(PublishPhase.idle);
    await t.pump();
    publishNotifier.setPhase(PublishPhase.uploading);
    await t.pump();

    // A stale _uploadStartTime from the first attempt would show the
    // inflated '1s' (and the ticker would never be recreated). A fresh
    // attempt must restart from 0s.
    expect(find.text('0s'), findsOneWidget);
    expect(find.text('1s'), findsNothing);

    // End on a terminal phase so the periodic ticker is cancelled before
    // the test ends.
    publishNotifier.setPhase(PublishPhase.completed);
    await t.pump();
  });
}
