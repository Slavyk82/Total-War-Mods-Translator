// Regression test for the Compile button gate in
// [PackCompilationEditorScreen].
//
// 2026-06-10 review (LOW / L11): the compile callback reads the conflict
// analysis with `.asData?.value`, which is null while the auto-triggered
// analysis is still AsyncLoading. Clicking Compile in that window skipped
// the unresolved-conflicts warning dialog entirely and compiled with
// conflicting keys merged last-writer-wins. The fix disables the Compile
// button while [compilationConflictAnalysisProvider] is loading (via the
// pre-existing [isAnalyzingConflictsProvider]); this test locks that in.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show AsyncValue, AsyncLoading, AsyncData;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/pack_compilation/models/conflict_analysis_result.dart';
import 'package:twmt/features/pack_compilation/providers/compilation_conflict_providers.dart';
import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/models/domain/game_installation.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/lists/small_text_button.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

/// Editor state stubbed to a compile-ready form (canCompile == true) so the
/// only variable under test is the conflict-analysis gate. reset() is a
/// no-op because the screen's post-frame callback calls it in "new" mode.
class _ReadyEditorNotifier extends CompilationEditorNotifier {
  @override
  CompilationEditorState build() => const CompilationEditorState(
        name: 'My compilation',
        prefix: '!!!_fr_compilation_twmt_',
        packName: 'my_pack',
        selectedLanguageId: 'lang-fr',
        selectedProjectIds: {'proj-1', 'proj-2'},
      );

  @override
  void reset() {}
}

/// Conflict-analysis notifier whose state is driven directly by the test.
/// analyze()/clear() are no-ops so the screen's ref.listen cannot overwrite
/// the state the test installed.
class _StubConflictAnalysis extends CompilationConflictAnalysis {
  AsyncValue<ConflictAnalysisResult?> initial = const AsyncLoading();

  @override
  AsyncValue<ConflictAnalysisResult?> build() => initial;

  void setState(AsyncValue<ConflictAnalysisResult?> value) {
    state = value;
  }

  @override
  Future<void> analyze({
    required List<String> projectIds,
    required String languageId,
  }) async {}

  @override
  void clear() {}
}

GameInstallation _installation() => GameInstallation(
      id: 'install-wh3',
      gameCode: 'wh3',
      gameName: 'Total War: WARHAMMER III',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets(
      'Compile button is disabled while conflict analysis is running and '
      're-enables once the analysis settles', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final analysis = _StubConflictAnalysis();

    await tester.pumpWidget(createThemedTestableWidget(
      const PackCompilationEditorScreen(compilationId: null),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        compilationEditorProvider.overrideWith(_ReadyEditorNotifier.new),
        compilationConflictAnalysisProvider.overrideWith(() => analysis),
        currentGameInstallationProvider
            .overrideWith((ref) async => _installation()),
      ],
    ));
    await tester.pump(); // post-frame callback (reset stub) + async resolves
    await tester.pump();

    SmallTextButton compileButton() => tester.widget<SmallTextButton>(
          find.widgetWithText(
            SmallTextButton,
            t.packCompilation.actions.compile,
          ),
        );

    expect(
      compileButton().onTap,
      isNull,
      reason: 'Compile must be disabled while the conflict analysis is in '
          'flight — proceeding would silently skip the unresolved-conflicts '
          'warning dialog',
    );

    analysis.setState(const AsyncData(null));
    await tester.pump();

    expect(
      compileButton().onTap,
      isNotNull,
      reason: 'Compile must re-enable once the analysis has settled',
    );
  });
}
