import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_list_screen.dart';
import 'package:twmt/models/domain/compilation.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Shared epoch used for all created/updated timestamps. Value is irrelevant
/// for widget tests (relative-date formatting isn't asserted) but anchors
/// the goldens via `clockProvider` in the golden test.
const int _epoch = 1_700_000_000;

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
      compilationsWithDetailsProvider.overrideWith((_) async => list),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('empty state renders new button', (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationListScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(list: const []),
    ));
    await t.pumpAndSettle();
    expect(find.text('No compilations yet'), findsOneWidget);
  });

  testWidgets('populated state renders rows', (t) async {
    await t.binding.setSurfaceSize(const Size(1280, 800));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(createThemedTestableWidget(
      const PackCompilationListScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _overrides(list: [_d('c1', 'Alpha', 3), _d('c2', 'Beta', 1)]),
    ));
    await t.pumpAndSettle();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('3 packs'), findsOneWidget);
    expect(find.text('1 packs'), findsOneWidget);
  });
}
