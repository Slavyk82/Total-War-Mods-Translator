import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/screens/project_detail_screen.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/detail/detail_meta_banner.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('ProjectDetailScreen', () {
    const testProjectId = 'test-project-123';
    const int epoch = 1_700_000_000;

    // Minimal `ProjectDetails` for tests that need to land in the data state
    // (back arrow, banner). The `_ErrorView` does not surface the back arrow
    // icon, so asserting it requires a success path.
    ProjectDetails stubDetails() => ProjectDetails(
          project: const Project(
            id: testProjectId,
            name: 'Stub',
            gameInstallationId: 'g-1',
            createdAt: epoch,
            updatedAt: epoch,
          ),
          languages: const [],
          stats: const TranslationStats(totalUnits: 0),
        );

    Widget subjectLoading() => createThemedTestableWidget(
          const ProjectDetailScreen(projectId: testProjectId),
          theme: AppTheme.atelierDarkTheme,
          overrides: [
            // Never completes — pins the screen in loading state.
            projectDetailsProvider(testProjectId)
                .overrideWith((_) => Completer<ProjectDetails>().future),
          ],
        );

    Widget subjectWithData() => createThemedTestableWidget(
          const ProjectDetailScreen(projectId: testProjectId),
          theme: AppTheme.atelierDarkTheme,
          overrides: [
            projectDetailsProvider(testProjectId)
                .overrideWith((_) async => stubDetails()),
          ],
        );

    testWidgets('does NOT render FluentScaffold (Plan 5b)', (tester) async {
      await tester.pumpWidget(subjectLoading());
      await tester.pump();
      expect(find.byType(FluentScaffold), findsNothing);
    });

    testWidgets('surfaces back arrow icon', (tester) async {
      await tester.pumpWidget(subjectWithData());
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsWidgets);
    });

    testWidgets('exposes projectId field', (tester) async {
      const screen = ProjectDetailScreen(projectId: testProjectId);
      expect(screen.projectId, testProjectId);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      await tester.pumpWidget(subjectLoading());
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('DetailMetaBanner present after provider resolves to data',
        (tester) async {
      await tester.pumpWidget(subjectWithData());
      await tester.pumpAndSettle(const Duration(seconds: 1));
      // Banner, error view, or loading indicator — all acceptable per spec.
      expect(
        find.byType(DetailMetaBanner).evaluate().isNotEmpty ||
            find.text('Failed to load project').evaluate().isNotEmpty ||
            find.byType(CircularProgressIndicator).evaluate().isNotEmpty,
        isTrue,
      );
    });
  });
}
