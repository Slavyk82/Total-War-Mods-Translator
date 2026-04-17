// Golden tests for the retokenised New Project wizard dialog
// (Plan 5d · Task 6).
//
// The dialog is a 3-step wizard rendered inside a [Dialog]. These goldens
// lock in the token-driven look across Atelier and Forge dark themes on
// step 1 (Basic info) with a populated game installations list so the
// CircularProgressIndicator branch is not surfaced.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/widgets/create_project/create_project_dialog.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

final _fakeGames = <GameInstallation>[
  GameInstallation(
    id: 'gi-wh3',
    gameCode: 'wh3',
    gameName: 'Total War: WARHAMMER III',
    installationPath: 'C:/fake/wh3',
    steamWorkshopPath: 'C:/fake/workshop/wh3',
    steamAppId: '1142710',
    isAutoDetected: true,
    isValid: true,
    lastValidatedAt: 0,
    createdAt: 0,
    updatedAt: 0,
  ),
  GameInstallation(
    id: 'gi-troy',
    gameCode: 'troy',
    gameName: 'A Total War Saga: TROY',
    installationPath: 'C:/fake/troy',
    steamWorkshopPath: 'C:/fake/workshop/troy',
    steamAppId: '1099410',
    isAutoDetected: true,
    isValid: true,
    lastValidatedAt: 0,
    createdAt: 0,
    updatedAt: 0,
  ),
];

const _fakeLanguages = <Language>[
  Language(
    id: 'lang-en',
    code: 'en',
    name: 'English',
    nativeName: 'English',
    isActive: true,
    isCustom: false,
  ),
  Language(
    id: 'lang-fr',
    code: 'fr',
    name: 'French',
    nativeName: 'Français',
    isActive: true,
    isCustom: false,
  ),
  Language(
    id: 'lang-de',
    code: 'de',
    name: 'German',
    nativeName: 'Deutsch',
    isActive: true,
    isCustom: false,
  ),
];

List<Override> _overrides() => [
      allGameInstallationsProvider
          .overrideWith((ref) async => _fakeGames),
      allLanguagesProvider.overrideWith((ref) async => _fakeLanguages),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pump(WidgetTester t, ThemeData theme) async {
    await t.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      createThemedTestableWidget(
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<String>(
                context: ctx,
                builder: (_) => const CreateProjectDialog(),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
        theme: theme,
        overrides: _overrides(),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
  }

  testWidgets('create project dialog atelier step 1', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(CreateProjectDialog),
      matchesGoldenFile('../goldens/create_project_atelier.png'),
    );
  });

  testWidgets('create project dialog forge step 1', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(CreateProjectDialog),
      matchesGoldenFile('../goldens/create_project_forge.png'),
    );
  });
}
