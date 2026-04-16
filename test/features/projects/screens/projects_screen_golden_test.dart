import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/models/domain/export_history.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

// Deterministic epoch so goldens stay byte-stable across runs.
const int _baseEpoch = 1_700_000_000;

/// Build a stable Project fixture so goldens are byte-deterministic across runs.
Project _project(
  String id,
  String name, {
  int updatedAt = _baseEpoch,
  bool hasModUpdateImpact = false,
}) =>
    Project(
      id: id,
      name: name,
      gameInstallationId: 'install-1',
      modSteamId: '1234567$id',
      createdAt: _baseEpoch,
      updatedAt: updatedAt,
      hasModUpdateImpact: hasModUpdateImpact,
    );

const _fr = Language(
  id: 'lang-fr',
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
);
const _de = Language(
  id: 'lang-de',
  code: 'de',
  name: 'German',
  nativeName: 'Deutsch',
);

ProjectLanguageWithInfo _plw({
  required String projectId,
  required Language language,
  required int total,
  required int translated,
}) =>
    ProjectLanguageWithInfo(
      projectLanguage: ProjectLanguage(
        id: '$projectId-${language.code}',
        projectId: projectId,
        languageId: language.id,
        createdAt: _baseEpoch,
        updatedAt: _baseEpoch,
      ),
      language: language,
      totalUnits: total,
      translatedUnits: translated,
    );

ExportHistory _export(String projectId, int exportedAt) => ExportHistory(
      id: 'export-$projectId',
      projectId: projectId,
      languages: '["fr"]',
      format: ExportFormat.pack,
      validatedOnly: false,
      outputPath: '/tmp/$projectId.pack',
      entryCount: 100,
      exportedAt: exportedAt,
    );

List<Override> _populatedOverrides() => [
      paginatedProjectsProvider.overrideWith((_) async => [
            // p1: needs update (update analysis with pending changes)
            ProjectWithDetails(
              project: _project('p1', 'Sigmars Heirs',
                  updatedAt: _baseEpoch + 100),
              languages: [
                _plw(
                    projectId: 'p1',
                    language: _fr,
                    total: 200,
                    translated: 40),
              ],
              updateAnalysis: const ModUpdateAnalysis(
                newUnitsCount: 5,
                removedUnitsCount: 0,
                modifiedUnitsCount: 2,
                totalPackUnits: 207,
                totalProjectUnits: 200,
              ),
            ),
            // p2: incomplete (progress in warn range), no export
            ProjectWithDetails(
              project: _project('p2', 'Warhammer Chaos Dwarves',
                  updatedAt: _baseEpoch + 200),
              languages: [
                _plw(
                    projectId: 'p2',
                    language: _fr,
                    total: 100,
                    translated: 30),
                _plw(
                    projectId: 'p2',
                    language: _de,
                    total: 100,
                    translated: 20),
              ],
            ),
            // p3: exported (progress 100%, up-to-date analysis, past export)
            ProjectWithDetails(
              project: _project('p3', 'Beastmen Overhaul',
                  updatedAt: _baseEpoch + 300),
              languages: [
                _plw(
                    projectId: 'p3',
                    language: _fr,
                    total: 100,
                    translated: 100),
              ],
              updateAnalysis: const ModUpdateAnalysis(
                newUnitsCount: 0,
                removedUnitsCount: 0,
                modifiedUnitsCount: 0,
                totalPackUnits: 100,
                totalProjectUnits: 100,
              ),
              lastPackExport: _export('p3', _baseEpoch + 250),
            ),
            // p4: export outdated (modified since last export)
            ProjectWithDetails(
              project: _project('p4', 'Norsca Reborn',
                  updatedAt: _baseEpoch + 600),
              languages: [
                _plw(
                    projectId: 'p4',
                    language: _de,
                    total: 100,
                    translated: 75),
              ],
              lastPackExport: _export('p4', _baseEpoch + 100),
            ),
            // p5: mod updated flag set (warn pill)
            ProjectWithDetails(
              project: _project('p5', 'Mortal Empires+',
                  updatedAt: _baseEpoch + 700, hasModUpdateImpact: true),
              languages: [
                _plw(
                    projectId: 'p5',
                    language: _fr,
                    total: 100,
                    translated: 60),
              ],
            ),
          ]),
      allLanguagesProvider.overrideWith((_) async => const <Language>[_fr, _de]),
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
