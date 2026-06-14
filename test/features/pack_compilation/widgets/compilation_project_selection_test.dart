// Widget coverage for [CompilationProjectSelectionSection].
//
// The section watches three providers — filteredProjectsProvider (the
// game+language filtered project list), projectFilterProvider (the search
// text) and showOnlySelectedProjectsProvider (the "only selected" toggle) —
// and renders one of several branches depending on the injected
// CompilationEditorState / currentGameAsync:
//
//  * gameInstallation == null            -> "select a game" message;
//  * selectedLanguageId == null          -> "select a language" message;
//  * project list loading                -> FluentSpinner;
//  * project list error                  -> failed-to-load message;
//  * empty list, no filter               -> "no projects with language";
//  * empty list, filter/onlySelected on  -> "no projects found" results;
//  * non-empty list                      -> ListRow per project + selection.
//
// The project list is driven by overriding projectsWithTranslationProvider for
// the matching ProjectFilterParams (value-equal), so the real filteredProjects
// derivation runs. Selection / search / toggle interactions are asserted via
// the injected callbacks and the editor + filter notifiers.
import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/pack_compilation/widgets/compilation_project_selection.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/common/fluent_spinner.dart';
import 'package:twmt/widgets/lists/list_row.dart';

import '../../../helpers/test_helpers.dart';

const _installId = 'install-wh3';
const _langId = 'lang-fr';

const _params = ProjectFilterParams(
  gameInstallationId: _installId,
  languageId: _langId,
);

GameInstallation _game() => const GameInstallation(
      id: _installId,
      gameCode: 'wh3',
      gameName: 'Total War: WARHAMMER III',
      installationPath: r'C:\games\wh3',
      createdAt: 0,
      updatedAt: 0,
    );

Project _project({required String id, required String name}) => Project(
      id: id,
      name: name,
      gameInstallationId: _installId,
      createdAt: 0,
      updatedAt: 0,
    );

ProjectWithTranslationInfo _info({
  required String id,
  required String name,
  int total = 10,
  int translated = 4,
}) =>
    ProjectWithTranslationInfo(
      project: _project(id: id, name: name),
      totalUnits: total,
      translatedUnits: translated,
    );

final _alpha = _info(id: 'a', name: 'Alpha Mod');
final _beta = _info(id: 'b', name: 'Beta Mod');

CompilationEditorState _state({
  String? languageId = _langId,
  Set<String> selected = const {},
}) =>
    CompilationEditorState(
      selectedLanguageId: languageId,
      selectedProjectIds: selected,
    );

void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

/// Editor notifier seeded with a fixed initial selection. The
/// "only selected" filter in filteredProjects watches the live editor notifier
/// (not the section's `state` prop), so tests that exercise that branch seed
/// the selection here.
class _SeededEditor extends CompilationEditorNotifier {
  _SeededEditor(this._initialSelection);

  final Set<String> _initialSelection;

  @override
  CompilationEditorState build() =>
      CompilationEditorState(selectedProjectIds: _initialSelection);
}

/// Pumps the section. [projectsOverride] replaces the DB-backed project list
/// provider for the matching params; pass null to leave it pending (loading).
/// [editorSelection] seeds the live editor notifier used by the only-selected
/// filter branch.
Future<void> _pump(
  WidgetTester tester, {
  required CompilationEditorState state,
  GameInstallation? game,
  Override? projectsOverride,
  Set<String>? editorSelection,
  void Function(String)? onToggle,
  VoidCallback? onDeselectAll,
}) async {
  _useTallSurface(tester);
  await tester.pumpWidget(createThemedTestableWidget(
    Scaffold(
      body: CompilationProjectSelectionSection(
        state: state,
        currentGameAsync: AsyncData<GameInstallation?>(game),
        onToggle: onToggle ?? (_) {},
        onDeselectAll: onDeselectAll ?? () {},
      ),
    ),
    theme: AppTheme.atelierDarkTheme,
    overrides: [
      if (projectsOverride != null) projectsOverride,
      if (editorSelection != null)
        compilationEditorProvider
            .overrideWith(() => _SeededEditor(editorSelection)),
    ],
  ));
  await tester.pump();
}

/// Resolved override of the project list provider with [items].
Override _projects(List<ProjectWithTranslationInfo> items) =>
    projectsWithTranslationProvider(_params).overrideWith((ref) async => items);

void main() {
  setUp(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('renders the header title always', (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    expect(find.text(t.packCompilation.labels.selectProjects), findsOneWidget);
  });

  testWidgets('shows the select-game message when no game is resolved',
      (tester) async {
    await _pump(tester, state: _state(), game: null);

    expect(
      find.text(t.packCompilation.hints.selectGameFirst),
      findsOneWidget,
    );
  });

  testWidgets('shows the select-language message when language is null',
      (tester) async {
    await _pump(
      tester,
      state: _state(languageId: null),
      game: _game(),
    );

    expect(
      find.text(t.packCompilation.hints.selectLanguageFirst),
      findsOneWidget,
    );
  });

  testWidgets('shows a spinner while the project list is loading',
      (tester) async {
    // No projects override resolution: provider stays in its initial loading
    // state on the first frame.
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: projectsWithTranslationProvider(_params).overrideWith(
          (ref) => Completer<List<ProjectWithTranslationInfo>>().future),
    );

    // First frame, the future never completes -> loading branch (FluentSpinner).
    expect(find.byType(FluentSpinner), findsOneWidget);
  });

  testWidgets('shows the failed-to-load message on error', (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: projectsWithTranslationProvider(_params)
          .overrideWith((ref) => Future<List<ProjectWithTranslationInfo>>.error(
                Exception('boom'),
              )),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(t.packCompilation.hints.failedToLoadProjects),
      findsOneWidget,
    );
  });

  testWidgets('shows the no-projects-with-language message for an empty list',
      (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects(const []),
    );
    await tester.pump();

    expect(
      find.text(t.packCompilation.hints.noProjectsWithLanguage),
      findsOneWidget,
    );
  });

  testWidgets('renders a row per project with progress text', (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    expect(find.byType(ListRow), findsNWidgets(2));
    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Beta Mod'), findsOneWidget);
    // Progress line: "4/10 · 40%".
    expect(find.textContaining('4/10'), findsWidgets);
  });

  testWidgets('tapping a project row invokes onToggle with its id',
      (tester) async {
    final toggled = <String>[];
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
      onToggle: toggled.add,
    );
    await tester.pump();

    await tester.tap(find.text('Alpha Mod'));
    await tester.pump();

    expect(toggled, ['a']);
  });

  testWidgets('selected projects render as selected rows', (tester) async {
    await _pump(
      tester,
      state: _state(selected: {'a'}),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    final rows = tester.widgetList<ListRow>(find.byType(ListRow)).toList();
    expect(rows.where((r) => r.selected), hasLength(1));
  });

  testWidgets('selection count pill shows the selected count and clears',
      (tester) async {
    var cleared = false;
    await _pump(
      tester,
      state: _state(selected: {'a', 'b'}),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
      onDeselectAll: () => cleared = true,
    );
    await tester.pump();

    expect(
      find.text(t.packCompilation.hints.selectedCount(count: 2)),
      findsOneWidget,
    );

    // The pill is tappable (close icon present) -> taps onDeselectAll.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(cleared, isTrue);
  });

  testWidgets('zero-count pill renders without a clear affordance',
      (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    expect(
      find.text(t.packCompilation.hints.selectedCount(count: 0)),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('typing in the search field filters the rendered rows',
      (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pump();

    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Beta Mod'), findsNothing);
  });

  testWidgets('clearing the search field restores the full list',
      (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Alpha');
    await tester.pump();
    expect(find.text('Beta Mod'), findsNothing);

    // The clear icon appears once text is present -> taps onClear (clears the
    // projectFilter notifier) and both projects render again.
    await tester.tap(find.byIcon(FluentIcons.dismiss_circle_24_regular));
    await tester.pump();

    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Beta Mod'), findsOneWidget);
  });

  testWidgets('search with no match shows the no-results message',
      (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'zzz-no-match');
    await tester.pump();

    expect(
      find.text(t.packCompilation.hints.noProjectsFound),
      findsOneWidget,
    );
    expect(
      find.text(t.packCompilation.hints.tryDifferentSearch),
      findsOneWidget,
    );
  });

  testWidgets('toggling the only-selected pill filters to selected projects',
      (tester) async {
    // 'a' selected in the live editor notifier -> turning on "only selected"
    // leaves only Alpha Mod (the filter reads the notifier, not the prop).
    await _pump(
      tester,
      state: _state(selected: {'a'}),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
      editorSelection: {'a'},
    );
    await tester.pump();

    expect(find.text('Beta Mod'), findsOneWidget);

    // The show-only-selected pill carries this tooltip label.
    await tester.tap(find.text(t.packCompilation.hints.showOnlySelected));
    await tester.pump();

    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Beta Mod'), findsNothing);
    // Empty-but-filtered branch (onlySelected on) is exercised when nothing
    // selected matches — covered by the next test.
  });

  testWidgets(
      'only-selected with no selection shows the no-results message',
      (tester) async {
    await _pump(
      tester,
      state: _state(),
      game: _game(),
      projectsOverride: _projects([_alpha, _beta]),
    );
    await tester.pump();

    await tester.tap(find.text(t.packCompilation.hints.showOnlySelected));
    await tester.pump();

    // onlySelected on + empty filtered list -> no-results (not no-projects).
    expect(
      find.text(t.packCompilation.hints.noProjectsFound),
      findsOneWidget,
    );
  });
}
