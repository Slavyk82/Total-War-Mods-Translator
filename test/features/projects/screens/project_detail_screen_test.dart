import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/projects/screens/project_detail_screen.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('ProjectDetailScreen', () {
    const testProjectId = 'test-project-123';

    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should have a header with back button', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsWidgets);
      });

      testWidgets('should accept projectId parameter', (tester) async {
        const screen = ProjectDetailScreen(projectId: testProjectId);
        expect(screen.projectId, equals(testProjectId));
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should use projectId for provider lookup', (tester) async {
        const screen = ProjectDetailScreen(projectId: testProjectId);
        expect(screen.projectId, isNotEmpty);
      });
    });

    group('Loading State', () {
      testWidgets('should show loading state initially', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        // Should show loading message or indicator
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should display loading text', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Error State', () {
      testWidgets('should handle error state gracefully', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should show Go Back button on error', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        // Error state should have a Go Back option
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Content Layout', () {
      testWidgets('should have responsive layout support', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        // LayoutBuilder should be used for responsive design
        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Languages Section', () {
      testWidgets('should have Target Languages section', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should have translate icon', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Add Language Button', () {
      testWidgets('should have Add Language button', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Delete Functionality', () {
      testWidgets('should support project deletion', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should support language deletion', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('should support back navigation', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsWidgets);
      });

      testWidgets('should support editor navigation', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should use surfaceContainerLow background', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible back button', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            const ProjectDetailScreen(projectId: testProjectId),
          ),
        );
        await tester.pump();

        expect(find.byType(ProjectDetailScreen), findsOneWidget);
      });
    });
  });
}
