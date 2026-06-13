// Widget coverage for [ConflictingProjectsPanel].
//
// The panel watches [compilationConflictAnalysisProvider] (for the AsyncValue
// branches) and the derived [conflictingProjectsProvider] (the per-project
// conflict counts). These tests drive each branch by overriding the analysis
// notifier with crafted [ConflictAnalysisResult] data so that
// [conflictingProjectsProvider] derives a deterministic project list:
//
//  * data with real conflicts -> conflict list (project names, counts, header
//    badge, info banner) plus the checkbox toggle callback and the
//    show-details dialog;
//  * data == null            -> "analysis will run" placeholder;
//  * data with only auto-resolvable duplicates -> "no conflicts" empty state;
//  * loading                 -> spinner;
//  * error                   -> error message.
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncValue, AsyncData, AsyncLoading, AsyncError;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/models/compilation_conflict.dart';
import 'package:twmt/features/pack_compilation/models/conflict_analysis_result.dart';
import 'package:twmt/features/pack_compilation/providers/compilation_conflict_providers.dart';
import 'package:twmt/features/pack_compilation/widgets/conflicting_projects_panel.dart';
import 'package:twmt/features/pack_compilation/widgets/project_conflicts_detail_dialog.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

/// Conflict-analysis notifier whose state is fixed by the test. analyze() and
/// clear() are no-ops so nothing overwrites the crafted state.
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

/// A single real (non-auto-resolvable) conflict between [first]/[second].
ConflictAnalysisResult _twoProjectConflict() => _result([
      _conflict(
        id: 'c1',
        key: 'shared_key',
        first: _entry(
          projectId: 'proj-1',
          projectName: 'Alpha Mod',
          sourceText: 'Hello',
        ),
        second: _entry(
          projectId: 'proj-2',
          projectName: 'Beta Mod',
          sourceText: 'Goodbye',
        ),
      ),
    ]);

/// Tall surface so nothing overflows.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _pumpPanel(
  WidgetTester tester,
  AsyncValue<ConflictAnalysisResult?> state, {
  Set<String> selectedProjectIds = const {'proj-1', 'proj-2'},
  void Function(String projectId)? onToggle,
}) async {
  _useTallSurface(tester);
  await tester.pumpWidget(createThemedTestableWidget(
    ConflictingProjectsPanel(
      selectedProjectIds: selectedProjectIds,
      onToggleProject: onToggle ?? (_) {},
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
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  testWidgets('header label always renders', (tester) async {
    await _pumpPanel(tester, const AsyncData(null));

    expect(
      find.text(t.packCompilation.labels.conflictingProjects),
      findsOneWidget,
    );
  });

  testWidgets('renders the no-analysis placeholder when data is null',
      (tester) async {
    await _pumpPanel(tester, const AsyncData(null));

    expect(
      find.text(t.packCompilation.conflicts.analysisWillRun),
      findsOneWidget,
    );
    expect(
      find.text(t.packCompilation.conflicts.whenYouClickGenerate),
      findsOneWidget,
    );
  });

  testWidgets('shows a loading spinner while analysis is in flight',
      (tester) async {
    await _pumpPanel(tester, const AsyncLoading());

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      find.text(t.packCompilation.conflicts.analyzingConflicts),
      findsOneWidget,
    );
  });

  testWidgets('shows the error state when analysis failed', (tester) async {
    await _pumpPanel(
      tester,
      AsyncError(Exception('boom'), StackTrace.current),
    );

    expect(
      find.text(t.packCompilation.conflicts.analysisFailed),
      findsOneWidget,
    );
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets(
      'shows the no-conflicts empty state when only auto-resolvable '
      'duplicates exist', (tester) async {
    final state = AsyncData(_result([
      _conflict(
        id: 'dup',
        key: 'dup_key',
        type: CompilationConflictType.duplicate,
        first: _entry(
          projectId: 'proj-1',
          projectName: 'Alpha Mod',
          sourceText: 'same',
        ),
        second: _entry(
          projectId: 'proj-2',
          projectName: 'Beta Mod',
          sourceText: 'same',
        ),
      ),
    ]));

    await _pumpPanel(tester, state);

    expect(
      find.text(t.packCompilation.conflicts.noConflictsDetected),
      findsOneWidget,
    );
    expect(
      find.text(t.packCompilation.conflicts.readyToCompile),
      findsOneWidget,
    );
  });

  testWidgets('renders the conflict list with project names and counts',
      (tester) async {
    await _pumpPanel(tester, AsyncData(_twoProjectConflict()));

    // Info banner.
    expect(
      find.text(t.packCompilation.conflicts.conflictInfo),
      findsOneWidget,
    );
    // Both conflicting projects appear in the list.
    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Beta Mod'), findsOneWidget);
    // Header count badge shows the number of conflicting projects (2).
    expect(find.text('2'), findsWidgets);
    // Per-project conflict count badges ('1' each).
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('tapping the checkbox invokes onToggleProject with the id',
      (tester) async {
    final toggled = <String>[];
    await _pumpPanel(
      tester,
      AsyncData(_twoProjectConflict()),
      onToggle: toggled.add,
    );

    // The first project name is rendered; tapping it opens the details dialog,
    // so to toggle we tap the checkbox (the selected orange box with a check).
    final checkmarks = find.byIcon(FluentIcons.checkmark_16_regular);
    // Tap the first checkbox region via the leading checkmark icon's ancestor.
    await tester.tap(checkmarks.first);
    await tester.pump();

    expect(toggled, isNotEmpty);
    expect({'proj-1', 'proj-2'}.contains(toggled.first), isTrue);
  });

  testWidgets('tapping a project name opens the details dialog',
      (tester) async {
    await _pumpPanel(tester, AsyncData(_twoProjectConflict()));

    await tester.tap(find.text('Alpha Mod'));
    await tester.pumpAndSettle();

    expect(find.byType(ProjectConflictsDetailDialog), findsOneWidget);
  });

  testWidgets('hovering an item exercises hover/highlight branches',
      (tester) async {
    await _pumpPanel(tester, AsyncData(_twoProjectConflict()));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    // Hover the project name -> name MouseRegion onEnter (primary color +
    // underline branch for selected items).
    await gesture.moveTo(tester.getCenter(find.text('Alpha Mod')));
    await tester.pumpAndSettle();

    // Hover the surrounding row -> item MouseRegion onEnter (orange bg branch).
    await gesture.moveTo(
      tester.getTopLeft(find.text('Alpha Mod')) - const Offset(20, 0),
    );
    await tester.pumpAndSettle();

    // Move away -> onExit branches.
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    expect(find.text('Alpha Mod'), findsOneWidget);
  });

  testWidgets('deselected project renders with strike-through styling path',
      (tester) async {
    // Selecting nothing exercises the !isSelected branch (line-through name,
    // transparent checkbox) for every item.
    await _pumpPanel(
      tester,
      AsyncData(_twoProjectConflict()),
      selectedProjectIds: const {},
    );

    expect(find.text('Alpha Mod'), findsOneWidget);
    expect(find.text('Beta Mod'), findsOneWidget);
    // No checkmark icons because no project is selected.
    expect(find.byIcon(FluentIcons.checkmark_16_regular), findsNothing);
  });
}
