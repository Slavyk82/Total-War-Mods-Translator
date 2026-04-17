import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/steam_publish/providers/publish_staging_provider.dart';
import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/screens/workshop_publish_screen.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Creates a tiny `.pack` file in the OS temp directory and returns a
/// [ProjectPublishItem] staged fixture pointing at it. The screen gates
/// the full wizard chrome on `_isUpdate`, which requires a non-empty
/// `publishedSteamId` *and* `hasPack` (via `File.existsSync`). Writing
/// a real placeholder file unlocks the full layout for the golden.
PublishableItem _makeFixture() {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final tempDir = Directory.systemTemp.createTempSync('twmt_workshop_pub_');
  final packPath = '${tempDir.path}/fr_compilation_twmt_my_pack.pack';
  File(packPath).writeAsBytesSync(List<int>.filled(2_500_000, 0));

  const project = Project(
    id: 'proj-1',
    name: 'French Translation - Warhammer III',
    gameInstallationId: 'wh3-install',
    createdAt: 1700000000,
    updatedAt: 1700000000,
    publishedSteamId: '2987654321',
    publishedAt: 1700003600,
  );
  final export = ExportHistory(
    id: 'exp-1',
    projectId: 'proj-1',
    languages: '["fr"]',
    format: ExportFormat.pack,
    validatedOnly: false,
    outputPath: packPath,
    fileSize: 2_500_000,
    entryCount: 12345,
    exportedAt: now - 600,
  );
  return ProjectPublishItem(
    export: export,
    project: project,
    languageCodes: const ['fr'],
  );
}

/// Test-only notifier that seeds the staging provider with a fixture.
class _StagedNotifier extends SinglePublishStagingNotifier {
  _StagedNotifier(this.fixture);
  final PublishableItem fixture;

  @override
  PublishableItem? build() => fixture;
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fixture = _makeFixture();
    await t.pumpWidget(createThemedTestableWidget(
      const WorkshopPublishScreen(),
      theme: theme,
      overrides: <Override>[
        singlePublishStagingProvider.overrideWith(
          () => _StagedNotifier(fixture),
        ),
      ],
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('workshop publish atelier pre-submit', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(WorkshopPublishScreen),
      matchesGoldenFile('../goldens/workshop_publish_atelier.png'),
    );
  });

  testWidgets('workshop publish forge pre-submit', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(WorkshopPublishScreen),
      matchesGoldenFile('../goldens/workshop_publish_forge.png'),
    );
  });
}
