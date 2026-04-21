// Screen tests for the migrated Projects screen (Plan 5a · Task 2).
//
// The pre-existing tests that asserted a FluentScaffold root and Fluent header
// were replaced when the screen moved to the FilterToolbar + ListRow archetype.
// These tests exercise the new chrome and row archetype, plus quick-filter
// pill routing, selection-mode toggling and batch-export gating.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/screens/projects_screen.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/shared/logging_providers.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/filter_pill.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import 'package:twmt/widgets/lists/list_row.dart';

import '../../../helpers/fakes/fake_logger.dart';
import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

Project _project(String id, String name) => Project(
      id: id,
      name: name,
      gameInstallationId: 'install-1',
      createdAt: 0,
      updatedAt: 0,
    );

ProjectWithDetails _details(String id, String name) => ProjectWithDetails(
      project: _project(id, name),
      languages: const [],
    );

const Language _french = Language(
  id: 'lang-fr',
  code: 'fr',
  name: 'French',
  nativeName: 'Français',
  isActive: true,
  isCustom: false,
);

List<Override> _populatedOverrides() => [
      paginatedProjectsProvider.overrideWith((_) async => [
            _details('p1', 'Project Alpha'),
            _details('p2', 'Project Bravo'),
            _details('p3', 'Project Charlie'),
          ]),
      allLanguagesProvider.overrideWith((_) async => const <Language>[]),
    ];

List<Override> _emptyOverrides() => [
      paginatedProjectsProvider
          .overrideWith((_) async => const <ProjectWithDetails>[]),
      allLanguagesProvider.overrideWith((_) async => const <Language>[]),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('ProjectsScreen shows FilterToolbar and ListRows',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(FilterToolbar), findsOneWidget);
    expect(find.byType(ListRow), findsNWidgets(3));
    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('Project Bravo'), findsOneWidget);
    expect(find.text('Project Charlie'), findsOneWidget);
  });

  testWidgets('ProjectsScreen empty state when no projects', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _emptyOverrides(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ListRow), findsNothing);
    expect(find.textContaining('No projects'), findsOneWidget);
  });

  testWidgets('Tapping a row triggers navigation callback', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Build a minimal router pairing the Projects screen with a dummy editor
    // screen so we can observe that the row tap's `openProjectEditor` call
    // resolves the target language and pushes the expected editor URL.
    final router = GoRouter(
      initialLocation: AppRoutes.projects,
      routes: [
        GoRoute(
          path: AppRoutes.projects,
          builder: (_, _) => const ProjectsScreen(),
        ),
        GoRoute(
          path: '${AppRoutes.projects}/:${AppRoutes.projectIdParam}/editor/:${AppRoutes.languageIdParam}',
          builder: (_, state) => Scaffold(
            body: Center(
              child: Text(
                'editor:'
                '${state.pathParameters[AppRoutes.projectIdParam]}:'
                '${state.pathParameters[AppRoutes.languageIdParam]}',
              ),
            ),
          ),
        ),
      ],
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        loggingServiceProvider.overrideWithValue(FakeLogger()),
        ..._populatedOverrides(),
        // Stub the target project's languages so `openProjectEditor` can
        // resolve a landing languageId without hitting the real repository.
        projectLanguagesProvider('p1')
            .overrideWith((_) async => [_projectLanguageDetails('fr-id', 'fr', 'French')]),
        // Fake settings service returning 'fr' as the default target language
        // — matches the stub above so resolution picks `fr-id`.
        settingsServiceProvider.overrideWithValue(_FakeSettingsService('fr')),
      ],
      child: MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    // Sanity: on the Projects screen, the editor marker is absent.
    expect(find.text('Project Alpha'), findsOneWidget);
    expect(find.text('editor:p1:fr-id'), findsNothing);

    // Tap the first row (Project Alpha) and let the router settle.
    await tester.tap(find.text('Project Alpha'));
    await tester.pumpAndSettle();

    // The dummy editor route received the expected project id + resolved
    // languageId, proving the row's onTap called `openProjectEditor(...)`
    // which in turn pushed `AppRoutes.translationEditor('p1', 'fr-id')`.
    expect(find.text('editor:p1:fr-id'), findsOneWidget);
  });

  testWidgets(
      'Tapping Needs Update pill routes through ProjectsFilterNotifier',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Spy notifier captures every setQuickFilter call so we can assert that
    // tapping the pill dispatches the correct ProjectQuickFilter without
    // depending on the downstream filter pipeline (paginatedProjectsProvider
    // is overridden with a static list).
    final notifier = _SpyProjectsFilterNotifier();
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        ..._populatedOverrides(),
        projectsFilterProvider.overrideWith(() => notifier),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilterPill, 'Needs Update'));
    await tester.pumpAndSettle();

    expect(notifier.recordedFilters, contains(ProjectQuickFilter.needsUpdate));
  });

  testWidgets('Selection-mode toggle reveals and hides the selection bar',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: _populatedOverrides(),
    ));
    await tester.pumpAndSettle();

    // Pre-condition: the selection bar (the conditional 3rd toolbar row)
    // is not rendered and the toggle button shows the 'Selection' label.
    expect(find.text('0 selected'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('Selection'), findsOneWidget);

    // Tap the _SelectionModeButton via its unique 'Selection' label.
    await tester.tap(find.text('Selection'));
    await tester.pumpAndSettle();

    // Selection bar now renders — "0 selected" badge and Cancel button are
    // the load-bearing signals that _SelectionBar is on-screen.
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // Tapping Cancel exits selection mode and removes the bar.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('0 selected'), findsNothing);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('Batch export button disabled when nothing selected',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Force selection mode ON with zero projects picked — canExport is false
    // and the tooltip should surface the "Select at least one project" gate.
    final notifier = _FixedBatchSelectionNotifier(
      const BatchProjectSelectionState(isSelectionMode: true),
    );
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        ..._populatedOverrides(),
        batchProjectSelectionProvider.overrideWith(() => notifier),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Select at least one project',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Batch export button enabled when selection + language picked',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Selection mode ON with one project selected AND a target language set
    // — canExport resolves true and the tooltip switches to the action copy.
    final notifier = _FixedBatchSelectionNotifier(
      const BatchProjectSelectionState(
        isSelectionMode: true,
        selectedProjectIds: {'p1'},
        selectedLanguageId: 'lang-fr',
      ),
    );
    await tester.pumpWidget(createThemedTestableWidget(
      const ProjectsScreen(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        paginatedProjectsProvider.overrideWith((_) async => [
              _details('p1', 'Project Alpha'),
              _details('p2', 'Project Bravo'),
            ]),
        allLanguagesProvider.overrideWith((_) async => const [_french]),
        batchProjectSelectionProvider.overrideWith(() => notifier),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (w) => w is Tooltip && w.message == 'Export selected projects as .pack files',
      ),
      findsOneWidget,
    );
    expect(find.text('1 selected'), findsOneWidget);
  });
}

/// Notifier spy that records every quick filter applied via [setQuickFilter].
/// Used to assert pill taps route through [ProjectsFilterNotifier] without
/// depending on the downstream filter pipeline.
class _SpyProjectsFilterNotifier extends ProjectsFilterNotifier {
  final List<ProjectQuickFilter> recordedFilters = [];

  @override
  ProjectsFilterState build() => const ProjectsFilterState();

  @override
  void setQuickFilter(ProjectQuickFilter filter) {
    recordedFilters.add(filter);
    state = state.copyWith(quickFilter: filter);
  }
}

/// Fake [SettingsService] that returns a fixed code for
/// `SettingsKeys.defaultTargetLanguage`. Matches the pattern used in
/// `test/features/projects/utils/open_project_editor_test.dart`.
class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(this._defaultCode);
  final String _defaultCode;

  @override
  Future<String> getString(String key, {String defaultValue = ''}) async {
    if (key == SettingsKeys.defaultTargetLanguage) return _defaultCode;
    return defaultValue;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

/// Build a minimal [ProjectLanguageDetails] for the row-tap navigation test.
/// The `languageId` is what `openProjectEditor` ultimately passes to the
/// translation editor route.
ProjectLanguageDetails _projectLanguageDetails(
  String languageId,
  String code,
  String name,
) {
  return ProjectLanguageDetails(
    projectLanguage: ProjectLanguage(
      id: 'pl_$languageId',
      projectId: 'p1',
      languageId: languageId,
      progressPercent: 0.0,
      createdAt: 1,
      updatedAt: 1,
    ),
    language: Language(
      id: languageId,
      code: code,
      name: name,
      nativeName: name,
    ),
  );
}

/// Notifier that pins [batchProjectSelectionProvider] to a caller-supplied
/// initial state. Lets tests drive the selection-bar / export-button UI into
/// a specific shape (selection-on with zero picks, or selection-on with a
/// language chosen) without walking through tap sequences.
///
/// Overrides [exitSelectionMode] to be a no-op because ProjectsScreen
/// `initState` calls it via a post-frame callback — without this the spy
/// state would be wiped before the first real frame.
class _FixedBatchSelectionNotifier extends BatchProjectSelectionNotifier {
  _FixedBatchSelectionNotifier(this._initial);

  final BatchProjectSelectionState _initial;

  @override
  BatchProjectSelectionState build() => _initial;

  @override
  void exitSelectionMode() {
    // Intentionally no-op so the pinned initial state survives the
    // ProjectsScreen `initState` post-frame reset.
  }
}
