import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Build a stable Project fixture so goldens are byte-deterministic across runs.
Project _project(String id, String name, {int updatedAt = 0}) => Project(
      id: id,
      name: name,
      gameInstallationId: 'install-1',
      modSteamId: '1234567$id',
      createdAt: 0,
      updatedAt: updatedAt,
    );

ProjectWithDetails _details(String id, String name, {int updatedAt = 0}) =>
    ProjectWithDetails(
      project: _project(id, name, updatedAt: updatedAt),
      languages: const [],
    );

List<Override> _populatedOverrides() => [
      paginatedProjectsProvider.overrideWith((_) async => [
            _details('p1', 'Sigmars Heirs', updatedAt: 1_700_000_000),
            _details('p2', 'Warhammer Chaos Dwarves', updatedAt: 1_700_050_000),
            _details('p3', 'Beastmen Overhaul', updatedAt: 1_700_100_000),
            _details('p4', 'Norsca Reborn', updatedAt: 1_700_150_000),
            _details('p5', 'Mortal Empires+', updatedAt: 1_700_200_000),
          ]),
      allLanguagesProvider.overrideWith((_) async => const <Language>[]),
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
      const ProjectsScreen(),
      theme: theme,
      overrides: overrides,
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('projects atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(ProjectsScreen),
      matchesGoldenFile('../goldens/projects_atelier_populated.png'),
    );
  });

  testWidgets('projects forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme, _populatedOverrides());
    await expectLater(
      find.byType(ProjectsScreen),
      matchesGoldenFile('../goldens/projects_forge_populated.png'),
    );
  });
}
