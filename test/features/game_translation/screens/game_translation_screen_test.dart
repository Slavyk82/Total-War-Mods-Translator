// Screen tests for the redesigned Game Translation screen.
//
// The screen moved to the FluentScaffold + HomeBackToolbar + FilterToolbar
// archetype (see lib/features/game_translation/screens/game_translation_screen.dart).
// The previous tests asserted a stale structure (literal padding values, a
// "ConsumerWidget" type check, hard-coded loading/error copy that no longer
// matched, and several placeholder assertions that only checked the screen
// rendered). These tests exercise the real chrome and the loading / error /
// empty / populated states against the current localized strings.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/game_translation/screens/game_translation_screen.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/features/projects/widgets/project_grid.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';

import '../../../helpers/test_bootstrap.dart';
import '../../../helpers/test_helpers.dart';

ProjectWithDetails _details(String id, String name) => ProjectWithDetails(
      project: Project(
        id: id,
        name: name,
        gameInstallationId: 'install-1',
        createdAt: 0,
        updatedAt: 0,
      ),
      languages: const [],
    );

/// Overrides for the default empty-list / no-packs scenario.
List<Override> _emptyNoPacksOverrides() => [
      gameTranslationProjectsProvider
          .overrideWith((ref) async => const <ProjectWithDetails>[]),
      hasLocalPacksProvider.overrideWith((ref) async => false),
    ];

/// Overrides for an empty list but with localization packs available, so the
/// empty state offers the create button instead of the warning.
List<Override> _emptyWithPacksOverrides() => [
      gameTranslationProjectsProvider
          .overrideWith((ref) async => const <ProjectWithDetails>[]),
      hasLocalPacksProvider.overrideWith((ref) async => true),
    ];

/// Overrides that keep the projects future pending so the loading state shows.
List<Override> _loadingOverrides() => [
      gameTranslationProjectsProvider.overrideWith(
        (ref) => Completer<List<ProjectWithDetails>>().future,
      ),
      hasLocalPacksProvider.overrideWith((ref) async => true),
    ];

/// Overrides that fail the projects future so the error state shows.
List<Override> _errorOverrides() => [
      gameTranslationProjectsProvider.overrideWith(
        (ref) async => throw Exception('boom'),
      ),
      hasLocalPacksProvider.overrideWith((ref) async => true),
    ];

/// Overrides with a populated project list so the grid renders.
List<Override> _populatedOverrides() => [
      gameTranslationProjectsProvider.overrideWith((ref) async => [
            _details('g1', 'English Overhaul'),
            _details('g2', 'French Overhaul'),
          ]),
      hasLocalPacksProvider.overrideWith((ref) async => true),
    ];

void main() {
  setUp(() async {
    await TestBootstrap.registerFakes();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> overrides,
    ThemeData? theme,
    bool settle = true,
  }) async {
    await tester.binding.setSurfaceSize(defaultTestScreenSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(createThemedTestableWidget(
      const GameTranslationScreen(),
      theme: theme ?? AppTheme.atelierDarkTheme,
      overrides: overrides,
    ));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('GameTranslationScreen', () {
    group('Chrome', () {
      testWidgets('renders inside a FluentScaffold', (tester) async {
        await pumpScreen(tester, overrides: _emptyNoPacksOverrides());
        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('has a const constructor', (tester) async {
        const screen = GameTranslationScreen();
        expect(screen, isNotNull);
      });

      testWidgets('shows the localized header title', (tester) async {
        await pumpScreen(tester, overrides: _emptyNoPacksOverrides());
        expect(find.text('Game Translation'), findsOneWidget);
      });

      testWidgets('shows the globe header icon', (tester) async {
        await pumpScreen(tester, overrides: _emptyNoPacksOverrides());
        expect(find.byIcon(FluentIcons.globe_24_regular), findsWidgets);
      });

      testWidgets('shows the create toolbar action', (tester) async {
        await pumpScreen(tester, overrides: _emptyWithPacksOverrides());
        expect(find.text('Create Game Translation'), findsWidgets);
      });
    });

    group('Loading State', () {
      testWidgets('shows a progress indicator while projects load',
          (tester) async {
        await pumpScreen(
          tester,
          overrides: _loadingOverrides(),
          settle: false,
        );

        expect(find.byType(CircularProgressIndicator), findsWidgets);
        expect(find.text('Loading game translations...'), findsOneWidget);
      });
    });

    group('Error State', () {
      testWidgets('shows the load-failed message and error icon',
          (tester) async {
        await pumpScreen(tester, overrides: _errorOverrides());

        expect(find.text('Error loading game translations'), findsOneWidget);
        expect(
          find.byIcon(FluentIcons.error_circle_24_regular),
          findsOneWidget,
        );
      });
    });

    group('Empty State', () {
      testWidgets('shows the empty-state title and subtitle', (tester) async {
        await pumpScreen(tester, overrides: _emptyWithPacksOverrides());

        expect(find.text('No game translations yet'), findsOneWidget);
        expect(
          find.text('Create a new translation to translate the base game'),
          findsOneWidget,
        );
      });

      testWidgets('offers a create action when packs are available',
          (tester) async {
        await pumpScreen(tester, overrides: _emptyWithPacksOverrides());
        // The empty state renders its own create button in addition to the
        // toolbar action.
        expect(find.text('Create Game Translation'), findsWidgets);
      });

      testWidgets('shows the no-packs warning when packs are missing',
          (tester) async {
        await pumpScreen(tester, overrides: _emptyNoPacksOverrides());

        expect(
          find.text('No localization packs found for this game'),
          findsWidgets,
        );
        expect(
          find.byIcon(FluentIcons.warning_24_regular),
          findsOneWidget,
        );
      });
    });

    group('Populated State', () {
      testWidgets('renders a ProjectGrid with the project names',
          (tester) async {
        await pumpScreen(tester, overrides: _populatedOverrides());

        expect(find.byType(ProjectGrid), findsOneWidget);
        expect(find.text('English Overhaul'), findsOneWidget);
        expect(find.text('French Overhaul'), findsOneWidget);
      });

      testWidgets('shows the translation count label', (tester) async {
        await pumpScreen(tester, overrides: _populatedOverrides());
        expect(find.text('2 translations'), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('renders with a dark theme', (tester) async {
        await pumpScreen(
          tester,
          overrides: _emptyNoPacksOverrides(),
          theme: AppTheme.atelierDarkTheme,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('renders with a light theme', (tester) async {
        await pumpScreen(
          tester,
          overrides: _emptyNoPacksOverrides(),
          theme: AppTheme.vellumLightTheme,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });
  });
}
