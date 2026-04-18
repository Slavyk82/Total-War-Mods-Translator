// Task 10 (workflow-improvements): after a successful pack compilation, the
// editor surfaces a NextStepCta routing to Steam Workshop. These tests pin
// the CTA to the success branch only and assert the tap navigates to
// /publishing/steam.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart' show ProviderScope;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:twmt/features/pack_compilation/providers/pack_compilation_providers.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_editor_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/workflow/next_step_cta.dart';

import '../../../helpers/test_bootstrap.dart';

/// Fake notifier pinned to a given state. The editor screen's initState
/// post-frame callback calls `reset()` (new mode) or `loadCompilation()`
/// (edit mode); both are overridden here to preserve the scripted state so
/// tests can observe every phase (idle/compiling/success/error) regardless
/// of which compilationId the screen was built with.
class _FakeEditorNotifier extends CompilationEditorNotifier {
  _FakeEditorNotifier(this._initial);
  final CompilationEditorState _initial;

  @override
  CompilationEditorState build() => _initial;

  @override
  void reset() {
    state = _initial;
  }

  @override
  void loadCompilation(CompilationWithDetails details) {
    state = _initial;
  }
}

CompilationEditorState _successState() => const CompilationEditorState(
      name: 'FR',
      prefix: '_fr_',
      packName: 'x',
      selectedLanguageId: 'fr',
      selectedProjectIds: {'p-1'},
      isCompiling: false,
      progress: 1.0,
      successMessage: 'Pack generated',
    );

CompilationEditorState _idleState() => const CompilationEditorState();

CompilationEditorState _compilingState() => const CompilationEditorState(
      name: 'FR',
      prefix: '_fr_',
      packName: 'x',
      selectedLanguageId: 'fr',
      selectedProjectIds: {'p-1'},
      isCompiling: true,
      progress: 0.4,
      currentStep: 'Processing...',
    );

CompilationEditorState _errorState() => const CompilationEditorState(
      name: 'FR',
      prefix: '_fr_',
      packName: 'x',
      selectedLanguageId: 'fr',
      selectedProjectIds: {'p-1'},
      isCompiling: false,
      errorMessage: 'boom',
    );

Widget _wrap({
  required CompilationEditorState editorState,
  GoRouter? router,
}) {
  final rc = router ??
      GoRouter(
        initialLocation: '/work/packs/new',
        routes: [
          GoRoute(
            path: '/work/packs/new',
            builder: (_, _) =>
                const PackCompilationEditorScreen(compilationId: null),
          ),
          GoRoute(
            path: '/publishing/steam',
            builder: (_, _) => const Scaffold(body: Text('STEAM_PUBLISH')),
          ),
        ],
      );
  return ProviderScope(
    overrides: [
      compilationEditorProvider.overrideWith(
        () => _FakeEditorNotifier(editorState),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.atelierDarkTheme,
      routerConfig: rc,
    ),
  );
}

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  testWidgets('renders NextStepCta on success state', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_wrap(editorState: _successState()));
    await t.pump();

    expect(find.byType(NextStepCta), findsOneWidget);
    expect(find.text('Next: Publish on Steam Workshop'), findsOneWidget);
  });

  testWidgets('hides NextStepCta on idle state', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_wrap(editorState: _idleState()));
    await t.pump();

    expect(find.byType(NextStepCta), findsNothing);
  });

  testWidgets('hides NextStepCta while compiling', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_wrap(editorState: _compilingState()));
    await t.pump();

    expect(find.byType(NextStepCta), findsNothing);
  });

  testWidgets('hides NextStepCta on error state', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    await t.pumpWidget(_wrap(editorState: _errorState()));
    await t.pump();

    expect(find.byType(NextStepCta), findsNothing);
  });

  testWidgets('tapping CTA navigates to /publishing/steam', (t) async {
    await t.binding.setSurfaceSize(const Size(1600, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final router = GoRouter(
      initialLocation: '/work/packs/new',
      routes: [
        GoRoute(
          path: '/work/packs/new',
          builder: (_, _) =>
              const PackCompilationEditorScreen(compilationId: null),
        ),
        GoRoute(
          path: '/publishing/steam',
          builder: (_, _) => const Scaffold(body: Text('STEAM_PUBLISH')),
        ),
      ],
    );

    await t.pumpWidget(_wrap(
      editorState: _successState(),
      router: router,
    ));
    await t.pump();

    await t.tap(find.byType(NextStepCta));
    await t.pumpAndSettle();

    expect(find.text('STEAM_PUBLISH'), findsOneWidget);
  });
}
