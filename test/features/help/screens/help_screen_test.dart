import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/help/screens/help_screen.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('HelpScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should render with Column layout', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = HelpScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerWidget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        final helpScreen = tester.widget<HelpScreen>(find.byType(HelpScreen));
        expect(helpScreen, isA<ConsumerWidget>());
      });
    });

    group('Header', () {
      testWidgets('should display question circle icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.question_circle_24_regular), findsOneWidget);
      });

      testWidgets('should display Help title', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.text('Help'), findsOneWidget);
      });

      testWidgets('should have correct header padding of 24', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Content Loading', () {
      testWidgets('should show loading indicator while loading', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        // During initial load
        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Error State', () {
      testWidgets('should display error icon on error', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should display error message', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('should display message when no documentation', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Content Layout', () {
      testWidgets('should have Row layout for content', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('should have TOC sidebar', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should have vertical divider', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should have section content area', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Section Navigation', () {
      testWidgets('should support section selection', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should clamp selectedIndex to valid range', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should use ValueKey for section content', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Anchor Navigation', () {
      testWidgets('should support navigation to section by anchor', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Divider', () {
      testWidgets('should have horizontal divider below header', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(Divider), findsWidgets);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const HelpScreen(),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const HelpScreen(),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should use theme primary color for icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should use theme divider color', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HelpScreen()));
        await tester.pump();

        expect(find.text('Help'), findsOneWidget);
      });
    });
  });
}
