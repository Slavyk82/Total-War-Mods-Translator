// Widget coverage for [ProjectConflictsDetailDialog].
//
// The dialog reads [compilationConflictAnalysisProvider] and renders a
// token-themed table of the unresolved conflicts that involve a specific
// project. These tests drive each AsyncValue branch (data/null, data with
// matching conflicts, data with no matching conflicts, loading, error) plus
// the close action, by overriding the analysis notifier with crafted data.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncValue, AsyncData, AsyncLoading, AsyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/models/compilation_conflict.dart';
import 'package:twmt/features/pack_compilation/models/conflict_analysis_result.dart';
import 'package:twmt/features/pack_compilation/providers/compilation_conflict_providers.dart';
import 'package:twmt/features/pack_compilation/widgets/project_conflicts_detail_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../helpers/test_helpers.dart';

/// Conflict-analysis notifier whose state is fixed by the test. analyze() and
/// clear() are no-ops so nothing can overwrite the crafted state.
class _StubConflictAnalysis extends CompilationConflictAnalysis {
  _StubConflictAnalysis(this._initial);

  final AsyncValue<ConflictAnalysisResult?> _initial;

  @override
  AsyncValue<ConflictAnalysisResult?> build() => _initial;

  @override
  Future<void> analyze({
    required List<String> projectIds,
    required String languageId,
  }) async {}

  @override
  void clear() {}
}

ConflictEntry _entry({
  required String projectId,
  required String projectName,
  required String sourceText,
  String unitId = 'unit',
}) =>
    ConflictEntry(
      projectId: projectId,
      projectName: projectName,
      unitId: '$projectId-$unitId',
      sourceText: sourceText,
    );

CompilationConflict _conflict({
  required String id,
  required String key,
  required ConflictEntry first,
  required ConflictEntry second,
  CompilationConflictType type =
      CompilationConflictType.keyCollisionDifferentSource,
}) =>
    CompilationConflict(
      id: id,
      key: key,
      conflictType: type,
      firstEntry: first,
      secondEntry: second,
    );

ConflictAnalysisResult _result(List<CompilationConflict> conflicts) =>
    ConflictAnalysisResult(
      conflicts: conflicts,
      summary: const ConflictSummary(
        totalCount: 0,
        keyCollisionCount: 0,
        translationConflictCount: 0,
        duplicateCount: 0,
      ),
      analyzedAt: 0,
      analyzedProjectIds: const ['proj-1', 'proj-2'],
      languageId: 'lang-fr',
    );

/// Tall surface so the 480-high dialog body never overflows.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpDialog(
  WidgetTester tester,
  AsyncValue<ConflictAnalysisResult?> state, {
  String projectId = 'proj-1',
  String projectName = 'Project One',
}) async {
  _useTallSurface(tester);
  await tester.pumpWidget(createThemedTestableWidget(
    ProjectConflictsDetailDialog(
      projectId: projectId,
      projectName: projectName,
    ),
    theme: AppTheme.atelierDarkTheme,
    overrides: [
      compilationConflictAnalysisProvider
          .overrideWith(() => _StubConflictAnalysis(state)),
    ],
  ));
  await tester.pump();
}

void main() {
  setUp(() async {
    // Force a deterministic locale for asserted strings.
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('shows the project name as subtitle', (tester) async {
    await _pumpDialog(
      tester,
      const AsyncData(null),
      projectName: 'My Project',
    );

    expect(find.text('My Project'), findsOneWidget);
  });

  testWidgets('renders no-analysis-data message when analysis is null',
      (tester) async {
    await _pumpDialog(tester, const AsyncData(null));

    expect(
      find.text(t.packCompilation.conflicts.noAnalysisData),
      findsOneWidget,
    );
  });

  testWidgets('shows a loading indicator while analysis is in flight',
      (tester) async {
    await _pumpDialog(tester, const AsyncLoading());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows the error message when analysis failed', (tester) async {
    await _pumpDialog(
      tester,
      AsyncError(Exception('boom'), StackTrace.current),
    );

    expect(
      find.textContaining(
        t.packCompilation.conflicts.errorPrefix(error: 'Exception: boom'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'renders the conflict table for conflicts involving the project '
      '(project is firstEntry)', (tester) async {
    final state = AsyncData(_result([
      _conflict(
        id: 'c1',
        key: 'my_key_one',
        first: _entry(
          projectId: 'proj-1',
          projectName: 'Project One',
          sourceText: 'Hello from one',
        ),
        second: _entry(
          projectId: 'proj-2',
          projectName: 'Project Two',
          sourceText: 'Hello from two',
        ),
      ),
    ]));

    await _pumpDialog(tester, state);

    // Header cells.
    expect(find.text(t.packCompilation.labels.conflictingKey), findsOneWidget);
    expect(find.text(t.packCompilation.labels.sourceTextThis), findsOneWidget);
    expect(
      find.text(t.packCompilation.labels.sourceTextConflicting),
      findsOneWidget,
    );

    // Row content: key + both project names and source texts.
    expect(find.text('my_key_one'), findsOneWidget);
    expect(find.text('Project One'), findsWidgets);
    expect(find.text('Project Two'), findsOneWidget);
    expect(find.text('Hello from one'), findsOneWidget);
    expect(find.text('Hello from two'), findsOneWidget);
  });

  testWidgets(
      'maps "this"/"other" correctly when the project is the secondEntry',
      (tester) async {
    final state = AsyncData(_result([
      _conflict(
        id: 'c2',
        key: 'key_second',
        first: _entry(
          projectId: 'proj-other',
          projectName: 'Other Project',
          sourceText: 'Other source',
        ),
        second: _entry(
          projectId: 'proj-1',
          projectName: 'Target Project',
          sourceText: 'Target source',
        ),
      ),
    ]));

    await _pumpDialog(tester, state, projectName: 'Target Project');

    expect(find.text('key_second'), findsOneWidget);
    expect(find.text('Other source'), findsOneWidget);
    expect(find.text('Target source'), findsOneWidget);
    expect(find.text('Other Project'), findsOneWidget);
  });

  testWidgets(
      'shows no-conflicts message when analysis has only conflicts for '
      'other projects or auto-resolvable duplicates', (tester) async {
    final state = AsyncData(_result([
      // Auto-resolvable duplicate involving the project -> filtered out.
      _conflict(
        id: 'dup',
        key: 'dup_key',
        type: CompilationConflictType.duplicate,
        first: _entry(
          projectId: 'proj-1',
          projectName: 'Project One',
          sourceText: 'same',
        ),
        second: _entry(
          projectId: 'proj-2',
          projectName: 'Project Two',
          sourceText: 'same',
        ),
      ),
      // Real conflict but not involving proj-1 -> filtered out.
      _conflict(
        id: 'other',
        key: 'other_key',
        first: _entry(
          projectId: 'proj-x',
          projectName: 'Project X',
          sourceText: 'x',
        ),
        second: _entry(
          projectId: 'proj-y',
          projectName: 'Project Y',
          sourceText: 'y',
        ),
      ),
    ]));

    await _pumpDialog(tester, state);

    expect(
      find.text(t.packCompilation.conflicts.noConflictsFound),
      findsOneWidget,
    );
  });

  testWidgets('close button pops the dialog', (tester) async {
    _useTallSurface(tester);
    final navKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(ProviderScopeForTest(
      navKey: navKey,
    ));
    await tester.pump();

    // Open the dialog.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectConflictsDetailDialog), findsOneWidget);

    await tester.tap(
      find.widgetWithText(SmallTextButton, t.common.actions.close),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ProjectConflictsDetailDialog), findsNothing);
  });
}

/// Minimal host that opens the dialog via showDialog so the close action has a
/// real route to pop. Defined as a widget to keep the test body declarative.
class ProviderScopeForTest extends StatelessWidget {
  const ProviderScopeForTest({super.key, required this.navKey});

  final GlobalKey<NavigatorState> navKey;

  @override
  Widget build(BuildContext context) {
    return createThemedTestableWidget(
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const ProjectConflictsDetailDialog(
                projectId: 'proj-1',
                projectName: 'Project One',
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        compilationConflictAnalysisProvider
            .overrideWith(() => _StubConflictAnalysis(const AsyncData(null))),
      ],
    );
  }
}
