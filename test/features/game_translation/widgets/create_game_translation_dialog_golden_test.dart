// Golden tests for the retokenised Game Translation setup dialog
// (Plan 5d · Task 5).
//
// The dialog is a 2-step wizard rendered inside a [Dialog]. These goldens
// lock in the token-driven look across Atelier and Forge dark themes on
// step 1 (source-pack selection) with a populated packs list so the
// CircularProgressIndicator branch is not surfaced.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/game_translation/widgets/create_game_translation/create_game_translation_dialog.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/services/game/game_localization_service.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Test double for [SelectedGame] that returns a fixed game without
/// touching settings services.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

const _fakeGame = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/fake/path',
);

final _fakePacks = <DetectedLocalPack>[
  DetectedLocalPack(
    languageCode: 'en',
    languageName: 'English',
    packFilePath: 'C:/fake/local_en.pack',
    fileSizeBytes: 245 * 1024 * 1024,
    lastModified: DateTime(2024, 3, 14, 9, 30),
  ),
  DetectedLocalPack(
    languageCode: 'fr',
    languageName: 'French',
    packFilePath: 'C:/fake/local_fr.pack',
    fileSizeBytes: 231 * 1024 * 1024,
    lastModified: DateTime(2024, 3, 14, 9, 30),
  ),
  DetectedLocalPack(
    languageCode: 'de',
    languageName: 'German',
    packFilePath: 'C:/fake/local_de.pack',
    fileSizeBytes: 240 * 1024 * 1024,
    lastModified: DateTime(2024, 3, 14, 9, 30),
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
      selectedGameProvider.overrideWith(() => _FakeSelectedGame(_fakeGame)),
      detectedLocalPacksProvider.overrideWith((ref) async => _fakePacks),
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
                builder: (_) => const CreateGameTranslationDialog(),
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

  testWidgets('create game translation dialog atelier step 1', (t) async {
    await pump(t, AppTheme.atelierDarkTheme);
    await expectLater(
      find.byType(CreateGameTranslationDialog),
      matchesGoldenFile('../goldens/create_game_translation_atelier.png'),
    );
  });

  testWidgets('create game translation dialog forge step 1', (t) async {
    await pump(t, AppTheme.forgeDarkTheme);
    await expectLater(
      find.byType(CreateGameTranslationDialog),
      matchesGoldenFile('../goldens/create_game_translation_forge.png'),
    );
  });
}
