// Screen tests for [GlossaryScreen].
//
// The screen walks through four precondition states before rendering the
// entries editor. These tests exercise each branch via provider overrides.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/features/glossary/screens/glossary_screen.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Test double for [SelectedGame] that returns a fixed [ConfiguredGame]
/// (or null) without touching the settings services.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._value);

  final ConfiguredGame? _value;

  @override
  Future<ConfiguredGame?> build() async => _value;
}

/// Test double for [SelectedGlossaryLanguage] that returns a fixed id
/// without hitting settings.
class _FakeSelectedGlossaryLanguage extends SelectedGlossaryLanguage {
  _FakeSelectedGlossaryLanguage(this._value);

  final String? _value;

  @override
  Future<String?> build(String gameCode) async => _value;

  @override
  Future<void> setLanguageId(String gameCode, String? languageId) async {
    state = AsyncData(languageId);
  }
}

Language _lang(String id, String code, String name) => Language(
      id: id,
      code: code,
      name: name,
      nativeName: name,
    );

Glossary _glossary({
  required String id,
  required String gameCode,
  required String targetLanguageId,
  int entryCount = 0,
}) {
  const epoch = 1_700_000_000;
  return Glossary(
    id: id,
    name: '$gameCode/$targetLanguageId',
    gameCode: gameCode,
    targetLanguageId: targetLanguageId,
    entryCount: entryCount,
    createdAt: epoch,
    updatedAt: epoch,
  );
}

GlossaryEntry _entry(String id, String glossaryId, String source) =>
    GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      sourceTerm: source,
      targetTerm: '$source (tr)',
      targetLanguageCode: 'fr',
      caseSensitive: false,
      createdAt: 1,
      updatedAt: 1,
    );

const ConfiguredGame _warhammer3 = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: '/fake/path',
);

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  testWidgets('empty state #1: no game selected prompts the user',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Select a game from the sidebar to view its glossary.'),
      findsOneWidget,
    );
  });

  testWidgets('empty state #2: game has no projects yet', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        selectedGameProvider
            .overrideWith(() => _FakeSelectedGame(_warhammer3)),
        hasProjectsForGameProvider(_warhammer3.code)
            .overrideWith((_) async => false),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No projects yet for ${_warhammer3.name}'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
          'A glossary will be generated automatically when you create your first project'),
      findsOneWidget,
    );
  });

  testWidgets('empty state #3: game with projects but no target languages',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        selectedGameProvider
            .overrideWith(() => _FakeSelectedGame(_warhammer3)),
        hasProjectsForGameProvider(_warhammer3.code)
            .overrideWith((_) async => true),
        glossaryAvailableLanguagesProvider(_warhammer3.code)
            .overrideWith((_) async => const <Language>[]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
          'No target languages configured for projects of ${_warhammer3.name}'),
      findsOneWidget,
    );
  });

  testWidgets('empty state #4: glossary exists but has zero entries',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final glossary = _glossary(
      id: 'g1',
      gameCode: _warhammer3.code,
      targetLanguageId: 'fr-id',
      entryCount: 0,
    );

    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        selectedGameProvider
            .overrideWith(() => _FakeSelectedGame(_warhammer3)),
        hasProjectsForGameProvider(_warhammer3.code)
            .overrideWith((_) async => true),
        glossaryAvailableLanguagesProvider(_warhammer3.code).overrideWith(
          (_) async => [_lang('fr-id', 'fr', 'French')],
        ),
        selectedGlossaryLanguageProvider(_warhammer3.code)
            .overrideWith(() => _FakeSelectedGlossaryLanguage('fr-id')),
        currentGlossaryProvider.overrideWith((_) async => glossary),
      ],
    ));
    await tester.pumpAndSettle();

    // Soft empty text surfaces in place of the grid.
    expect(
      find.text('No entries yet. Import a CSV or add your first entry.'),
      findsOneWidget,
    );
    expect(find.byType(SfDataGrid), findsNothing);
  });

  testWidgets('nominal: glossary with entries renders the data grid',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final glossary = _glossary(
      id: 'g1',
      gameCode: _warhammer3.code,
      targetLanguageId: 'fr-id',
      entryCount: 2,
    );

    await tester.pumpWidget(createThemedTestableWidget(
      const GlossaryScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        selectedGameProvider
            .overrideWith(() => _FakeSelectedGame(_warhammer3)),
        hasProjectsForGameProvider(_warhammer3.code)
            .overrideWith((_) async => true),
        glossaryAvailableLanguagesProvider(_warhammer3.code).overrideWith(
          (_) async => [_lang('fr-id', 'fr', 'French')],
        ),
        selectedGlossaryLanguageProvider(_warhammer3.code)
            .overrideWith(() => _FakeSelectedGlossaryLanguage('fr-id')),
        currentGlossaryProvider.overrideWith((_) async => glossary),
        glossaryEntriesProvider(
          glossaryId: 'g1',
          targetLanguageCode: null,
        ).overrideWith(
          (_) async => [
            _entry('e1', 'g1', 'Dwarf'),
            _entry('e2', 'g1', 'Elf'),
          ],
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SfDataGrid), findsOneWidget);
    expect(find.text('Dwarf'), findsOneWidget);
    expect(find.text('Elf'), findsOneWidget);
  });
}
