// Golden tests for the migrated Steam Publish screen (Plan 5a · Task 4).
//
// Fixtures exercise every publish-state badge: Published (up to date),
// Published (outdated), Unpublished (pack ready) and No pack. Relative date
// cells read the [clockProvider] override so rendering stays byte-stable.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:twmt/features/steam_publish/providers/steam_publish_providers.dart';
import 'package:twmt/features/steam_publish/screens/steam_publish_screen.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

const int _baseEpoch = 1_700_000_000;

String _createTempPack(String id) {
  final dir = Directory.systemTemp.createTempSync('twmt-steam-publish-$id-');
  addTearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  });
  final packPath = p.join(dir.path, '$id.pack');
  File(packPath).writeAsBytesSync(const []);
  return packPath;
}

ProjectPublishItem _project({
  required String id,
  required String name,
  String? publishedSteamId,
  int? publishedAt,
  int exportedAt = 0,
  bool hasPack = false,
}) {
  final outputPath = hasPack ? _createTempPack(id) : '';
  return ProjectPublishItem(
    export: hasPack
        ? ExportHistory(
            id: 'e-$id',
            projectId: id,
            languages: '["en"]',
            format: ExportFormat.pack,
            validatedOnly: false,
            outputPath: outputPath,
            entryCount: 10,
            exportedAt: exportedAt,
          )
        : null,
    project: Project(
      id: id,
      name: name,
      gameInstallationId: 'g1',
      createdAt: 0,
      updatedAt: 0,
      publishedSteamId: publishedSteamId,
      publishedAt: publishedAt,
    ),
    languageCodes: const ['en'],
  );
}

List<PublishableItem> _populatedItems() => [
      // Published and up to date.
      _project(
        id: 'p1',
        name: 'Sigmars Heirs',
        publishedSteamId: '111111',
        publishedAt: _baseEpoch,
        exportedAt: _baseEpoch,
        hasPack: true,
      ),
      // Published but outdated (pack newer than publish).
      _project(
        id: 'p2',
        name: 'Warhammer Chaos Dwarves',
        publishedSteamId: '222222',
        publishedAt: _baseEpoch,
        exportedAt: _baseEpoch + 3600,
        hasPack: true,
      ),
      // Pack ready, never published.
      _project(
        id: 'p3',
        name: 'Beastmen Overhaul',
        exportedAt: _baseEpoch - 7200,
        hasPack: true,
      ),
      // No pack yet.
      _project(
        id: 'p4',
        name: 'Norsca Reborn',
      ),
    ];

// Pinned "now" so relative-date cells render deterministically.
final DateTime _pinnedNow =
    DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
        .add(const Duration(days: 30));

List<Override> _populatedOverrides() {
  final items = _populatedItems();
  final outdated = items
      .where((e) => e.publishedAt != null && e.exportedAt > e.publishedAt!)
      .length;
  final noPack = items.where((e) => !e.hasPack).length;
  return [
    clockProvider.overrideWithValue(() => _pinnedNow),
    publishableItemsProvider.overrideWith((_) async => items),
    filteredPublishableItemsProvider.overrideWithValue(items),
    outdatedPublishableItemsCountProvider.overrideWithValue(outdated),
    noPackPublishableItemsCountProvider.overrideWithValue(noPack),
  ];
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
    List<Override> overrides,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const SteamPublishScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('steam publish atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(SteamPublishScreen),
      matchesGoldenFile('../goldens/steam_publish_atelier_populated.png'),
    );
  });

  testWidgets('steam publish forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(SteamPublishScreen),
      matchesGoldenFile('../goldens/steam_publish_forge_populated.png'),
    );
  });
}
