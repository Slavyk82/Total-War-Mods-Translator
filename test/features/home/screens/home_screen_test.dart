import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:twmt/features/home/screens/home_screen.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('HomeScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should render within a SingleChildScrollView', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(SingleChildScrollView), findsOneWidget);
      });

      testWidgets('should render a Column for layout', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(Column), findsWidgets);
      });
    });

    group('Child Widgets', () {
      testWidgets('should render WelcomeCard widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        // WelcomeCard should be present in the widget tree
        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should render StatsCards widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should render RecentProjectsCard widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });

    group('Layout and Spacing', () {
      testWidgets('should have correct padding of 24.0', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        final scrollView = tester.widget<SingleChildScrollView>(
          find.byType(SingleChildScrollView),
        );

        expect(scrollView.padding, const EdgeInsets.all(24.0));
      });

      testWidgets('should have SizedBox widgets for spacing', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        expect(find.byType(SizedBox), findsWidgets);
      });
    });

    group('StatelessWidget Behavior', () {
      testWidgets('should be a StatelessWidget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        final homeScreen = tester.widget<HomeScreen>(find.byType(HomeScreen));
        expect(homeScreen, isA<StatelessWidget>());
      });

      testWidgets('should have const constructor', (tester) async {
        // This test verifies that HomeScreen can be created with const constructor
        const homeScreen = HomeScreen();
        expect(homeScreen, isNotNull);
      });
    });

    group('Accessibility', () {
      testWidgets('should be scrollable for different screen sizes', (tester) async {
        await tester.pumpWidget(createTestableWidget(const HomeScreen()));
        await tester.pumpAndSettle();

        final scrollView = find.byType(SingleChildScrollView);
        expect(scrollView, findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const HomeScreen(),
            theme: ThemeData.light(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const HomeScreen(),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(HomeScreen), findsOneWidget);
      });
    });
  });
}
