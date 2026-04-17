import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/screens/project_detail_screen.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

const int _epoch = 1_700_000_000;

Project _project() => Project(
      id: 'p-1',
      name: 'Sigmars Heirs',
      gameInstallationId: 'install-1',
      modSteamId: '1234567',
      createdAt: _epoch,
      updatedAt: _epoch,
    );

const _fr = Language(id: 'l-fr', code: 'fr', name: 'French', nativeName: 'Français');
const _de = Language(id: 'l-de', code: 'de', name: 'German', nativeName: 'Deutsch');

ProjectLanguageDetails _pld(Language lang, int total, int translated) =>
    ProjectLanguageDetails(
      projectLanguage: ProjectLanguage(
        id: 'pl-${lang.code}',
        projectId: 'p-1',
        languageId: lang.id,
        createdAt: _epoch,
        updatedAt: _epoch,
      ),
      language: lang,
      totalUnits: total,
      translatedUnits: translated,
      pendingUnits: total - translated,
    );

List<Override> _populatedOverrides() => [
      projectDetailsProvider('p-1').overrideWith((_) async => ProjectDetails(
            project: _project(),
            languages: [
              _pld(_fr, 100, 60),
              _pld(_de, 100, 100),
            ],
            stats: const TranslationStats(
              totalUnits: 200,
              translatedUnits: 160,
              pendingUnits: 40,
              needsReviewUnits: 2,
              tmReuseRate: 0.234,
              tokensUsed: 24000,
            ),
          )),
      projectsWithDetailsProvider.overrideWith((_) async => const []),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpUnder(
    WidgetTester tester,
    ThemeData theme,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectDetailScreen(projectId: 'p-1'),
      theme: theme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('project detail atelier populated', (t) async {
    await pumpUnder(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(ProjectDetailScreen),
      matchesGoldenFile('../goldens/project_detail_atelier.png'),
    );
  });

  testWidgets('project detail forge populated', (t) async {
    await pumpUnder(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(ProjectDetailScreen),
      matchesGoldenFile('../goldens/project_detail_forge.png'),
    );
  });
}
