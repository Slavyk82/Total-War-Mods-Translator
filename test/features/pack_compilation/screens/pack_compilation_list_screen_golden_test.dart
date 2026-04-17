// Golden tests for the migrated Pack Compilation list screen (Plan 5c · Task 4).
//
// Duplicates the `_c` / `_d` / `_overrides` helpers from the widget test so
// this file is self-contained. The clock is pinned via `clockProvider` so the
// relative-date cells stay byte-stable between runs.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_list_screen.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/clock_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Base epoch used by fixture compilations. `updatedAt` is stored in
/// milliseconds on the [Compilation] model so we multiply the seconds epoch
/// by 1000 before assignment.
const int _epoch = 1_700_000_000;

/// Pinned "now" for the golden tests. Offset by 3 days from the fixture's
/// `updatedAt` so the relative-date cell reads "3 days".
final DateTime _pinnedNow =
    DateTime.fromMillisecondsSinceEpoch(_epoch * 1000)
        .add(const Duration(days: 3));

Compilation _c(String id, String name) => Compilation(
      id: id,
      name: name,
      prefix: 'p',
      packName: '$name.pack',
      languageId: 'fr',
      gameInstallationId: 'g',
      createdAt: _epoch,
      updatedAt: _epoch * 1000,
    );

CompilationWithDetails _d(String id, String name, int projCount) =>
    CompilationWithDetails(
      compilation: _c(id, name),
      projects: List.generate(
        projCount,
        (i) => Project(
          id: '$id-$i',
          name: 'p$i',
          gameInstallationId: 'g',
          createdAt: _epoch,
          updatedAt: _epoch,
        ),
      ),
      projectCount: projCount,
      gameInstallation: const GameInstallation(
        id: 'g',
        gameCode: 'warhammer_iii',
        gameName: 'Warhammer III',
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
    );

List<Override> _overrides({required List<CompilationWithDetails> list}) => [
      clockProvider.overrideWithValue(() => _pinnedNow),
      compilationsWithDetailsProvider.overrideWith((_) async => list),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationListScreen(),
      theme: theme,
      overrides: _overrides(
        list: [_d('c1', 'Imperial Bundle', 4), _d('c2', 'Chaos Pack', 2)],
      ),
    ));
    await t.pumpAndSettle();
  }

  testWidgets('pack compilation list atelier populated', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(PackCompilationListScreen),
      matchesGoldenFile('../goldens/pack_compilation_list_atelier.png'),
    );
  });

  testWidgets('pack compilation list forge populated', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(PackCompilationListScreen),
      matchesGoldenFile('../goldens/pack_compilation_list_forge.png'),
    );
  });
}
