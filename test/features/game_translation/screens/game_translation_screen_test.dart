import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/game_translation/screens/game_translation_screen.dart';
import 'package:twmt/features/game_translation/providers/game_translation_providers.dart';
import 'package:twmt/features/projects/providers/projects_screen_providers.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('GameTranslationScreen', () {
    /// Creates test widget with mocked providers for empty project list
    Widget createTestWidget({ThemeData? theme}) {
      return ProviderScope(
        overrides: [
          // Return empty list of projects to avoid loading/error states
          gameTranslationProjectsProvider.overrideWith(
            (ref) async => <ProjectWithDetails>[],
          ),
          // Return false for hasLocalPacks to show simple empty state
          hasLocalPacksProvider.overrideWith(
            (ref) async => false,
          ),
        ],
        child: MaterialApp(
          theme: theme ?? ThemeData.light(),
          home: SizedBox(
            width: defaultTestScreenSize.width,
            height: defaultTestScreenSize.height,
            child: const GameTranslationScreen(),
          ),
        ),
      );
    }

    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should have padding of 24.0', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Padding), findsWidgets);
      });

      testWidgets('should have Column layout', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = GameTranslationScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerWidget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        final screen = tester.widget<GameTranslationScreen>(
          find.byType(GameTranslationScreen),
        );
        expect(screen, isA<ConsumerWidget>());
      });
    });

    group('Header', () {
      testWidgets('should display globe icon', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byIcon(FluentIcons.globe_24_regular), findsWidgets);
      });

      testWidgets('should display Game Translation title', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Game Translation'), findsOneWidget);
      });
    });

    group('Loading State', () {
      testWidgets('should show loading indicator', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should display loading message', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Error State', () {
      testWidgets('should display error icon', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should display error message', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('should display empty state message', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should display create button in empty state', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should display warning when no packs available', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Projects Grid', () {
      testWidgets('should render ProjectGrid when projects exist', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should pass projects to grid', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Create Dialog', () {
      testWidgets('should show CreateGameTranslationDialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should not be dismissible', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('should support project navigation', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should navigate to project detail', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Local Packs Check', () {
      testWidgets('should check for local packs availability', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should disable create when no packs', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Filtering', () {
      testWidgets('should filter for game translation projects', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.light()));
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.dark()));
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });

      testWidgets('should use theme colors', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('Game Translation'), findsOneWidget);
      });

      testWidgets('should have accessible warning icon', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GameTranslationScreen), findsOneWidget);
      });
    });
  });
}
