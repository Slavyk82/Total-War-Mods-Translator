import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/mods/models/scan_log_message.dart';
import 'package:twmt/features/mods/providers/mods_screen_providers.dart';
import 'package:twmt/features/mods/screens/mods_screen.dart';
import 'package:twmt/models/domain/detected_mod.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project_metadata.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// Deterministic epoch so goldens stay byte-stable across runs.
const int _baseEpoch = 1_700_000_000;

DetectedMod _mod(
  String id,
  String name, {
  int? timeUpdated,
  int? localFileLastModified,
  bool isAlreadyImported = false,
  bool isHidden = false,
  int subscribers = 0,
  ModUpdateAnalysis? analysis,
}) =>
    DetectedMod(
      workshopId: id,
      name: name,
      packFilePath: '/tmp/$id.pack',
      imageUrl: null,
      metadata: subscribers > 0
          ? ProjectMetadata(modSubscribers: subscribers)
          : null,
      isAlreadyImported: isAlreadyImported,
      isHidden: isHidden,
      timeUpdated: timeUpdated,
      localFileLastModified: localFileLastModified,
      updateAnalysis: analysis,
    );

List<DetectedMod> _populatedMods() => [
      // Not imported, recent update.
      _mod(
        '1001',
        'Sigmars Heirs',
        timeUpdated: _baseEpoch,
        localFileLastModified: _baseEpoch,
        subscribers: 12345,
      ),
      // Imported, up to date.
      _mod(
        '1002',
        'Warhammer Chaos Dwarves',
        timeUpdated: _baseEpoch,
        localFileLastModified: _baseEpoch,
        isAlreadyImported: true,
        subscribers: 6789,
        analysis: const ModUpdateAnalysis(
          newUnitsCount: 0,
          removedUnitsCount: 0,
          modifiedUnitsCount: 0,
          totalPackUnits: 100,
          totalProjectUnits: 100,
        ),
      ),
      // Imported, needs download (local file < Steam time).
      _mod(
        '1003',
        'Beastmen Overhaul',
        timeUpdated: _baseEpoch + 1000,
        localFileLastModified: _baseEpoch,
        isAlreadyImported: true,
        subscribers: 2500,
      ),
      // Imported, has translation changes.
      _mod(
        '1004',
        'Norsca Reborn',
        timeUpdated: _baseEpoch + 200,
        localFileLastModified: _baseEpoch + 300,
        isAlreadyImported: true,
        subscribers: 980,
        analysis: const ModUpdateAnalysis(
          newUnitsCount: 5,
          removedUnitsCount: 0,
          modifiedUnitsCount: 2,
          totalPackUnits: 107,
          totalProjectUnits: 100,
        ),
      ),
      // Not imported, no subscribers fallback.
      _mod(
        '1005',
        'Mortal Empires+',
        timeUpdated: _baseEpoch - 86400 * 30,
        localFileLastModified: _baseEpoch - 86400 * 30,
      ),
    ];

// Pinned "now" so _UpdatedCell's relative-date formatter renders stable output
// across runs (30 days after the base epoch puts all mods into the "months"
// bucket deterministically).
final DateTime _pinnedNow =
    DateTime.fromMillisecondsSinceEpoch(_baseEpoch * 1000)
        .add(const Duration(days: 30));

List<Override> _populatedOverrides() => [
      clockProvider.overrideWithValue(() => _pinnedNow),
      scanLogStreamProvider.overrideWithValue(
        const Stream<ScanLogMessage>.empty(),
      ),
      filteredModsProvider.overrideWith((_) => _populatedMods()),
      modsIsLoadingProvider.overrideWith((_) => false),
      modsErrorProvider.overrideWith((_) => null),
      totalModsCountProvider.overrideWith((_) async => 5),
      notImportedModsCountProvider.overrideWith((_) async => 2),
      needsUpdateModsCountProvider.overrideWith((_) async => 2),
      hiddenModsCountProvider.overrideWith((_) async => 0),
      projectsWithPendingChangesCountProvider.overrideWith((_) async => 1),
    ];

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
      const ModsScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('mods atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(ModsScreen),
      matchesGoldenFile('../goldens/mods_atelier_populated.png'),
    );
  });

  testWidgets('mods forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(ModsScreen),
      matchesGoldenFile('../goldens/mods_forge_populated.png'),
    );
  });
}
