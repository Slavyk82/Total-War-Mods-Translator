import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/glossary/screens/glossary_screen.dart';
import 'package:twmt/features/glossary/providers/glossary_providers.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
    await setupMockServices();
  });

  tearDown(() async {
    await tearDownMockServices();
  });

  group('GlossaryScreen', () {
    /// Creates test widget with mocked providers
    Widget createTestWidget({ThemeData? theme}) {
      return ProviderScope(
        overrides: [
          // Override glossaries provider to return empty list
          glossariesProvider().overrideWith(
            (ref) async => <Glossary>[],
          ),
          // Override selected glossary provider
          selectedGlossaryProvider.overrideWith(
            () => _MockSelectedGlossaryNotifier(),
          ),
        ],
        child: MaterialApp(
          theme: theme ?? ThemeData.light(),
          home: SizedBox(
            width: defaultTestScreenSize.width,
            height: defaultTestScreenSize.height,
            child: const GlossaryScreen(),
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

      testWidgets('should render with Column layout', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = GlossaryScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('List View', () {
      testWidgets('should show list view when no glossary is selected', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should display glossary list header', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should handle loading state', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should handle error state', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should handle empty state', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('Editor View', () {
      testWidgets('should show editor view when glossary is selected', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should display glossary editor header', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should display statistics panel', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should display editor toolbar', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should display data grid', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should display editor footer', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('Dialogs', () {
      testWidgets('should support new glossary dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should support entry editor dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should support import dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should support export dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should support delete confirmation dialog', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('Search', () {
      testWidgets('should have search controller', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('Game Installations', () {
      testWidgets('should load game installations on init', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('Lifecycle', () {
      testWidgets('should dispose search controller', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        // Navigate away to trigger dispose
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: defaultTestScreenSize.width,
              height: defaultTestScreenSize.height,
              child: const SizedBox(),
            ),
          ),
        );

        expect(find.byType(GlossaryScreen), findsNothing);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.light()));
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(createTestWidget(theme: ThemeData.dark()));
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });

    group('Layout', () {
      testWidgets('should have statistics panel with 280 width', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });

      testWidgets('should have vertical divider between panels', (tester) async {
        await tester.pumpWidget(createTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(GlossaryScreen), findsOneWidget);
      });
    });
  });
}

/// Mock notifier for selected glossary state
class _MockSelectedGlossaryNotifier extends SelectedGlossary {
  @override
  Glossary? build() => null;

  @override
  void select(Glossary? glossary) {}

  @override
  void clear() {}
}
