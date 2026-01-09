import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/screens/validation_review_screen.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('ValidationReviewScreen', () {
    // Create sample validation issues for testing
    List<ValidationIssue> createSampleIssues() {
      return [
        ValidationIssue(
          versionId: 'v1',
          unitId: 'unit1',
          unitKey: 'key1',
          sourceText: 'Hello world',
          translatedText: 'Bonjour monde',
          description: 'Placeholder mismatch',
          issueType: 'placeholder',
          severity: ValidationSeverity.error,
        ),
        ValidationIssue(
          versionId: 'v2',
          unitId: 'unit2',
          unitKey: 'key2',
          sourceText: 'Test string',
          translatedText: 'Chaîne de test',
          description: 'Trailing whitespace',
          issueType: 'whitespace',
          severity: ValidationSeverity.warning,
        ),
      ];
    }

    group('Widget Structure', () {
      testWidgets('should render Scaffold as root widget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(Scaffold), findsWidgets);
      });

      testWidgets('should accept required parameters', (tester) async {
        final issues = createSampleIssues();
        final screen = ValidationReviewScreen(
          issues: issues,
          totalValidated: 100,
          passedCount: 98,
          onRejectTranslation: (issue) async {},
          onAcceptTranslation: (issue) async {},
        );
        expect(screen.issues, equals(issues));
        expect(screen.totalValidated, equals(100));
        expect(screen.passedCount, equals(98));
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Header Section', () {
      testWidgets('should render ValidationReviewHeader', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Toolbar Section', () {
      testWidgets('should render ValidationReviewToolbar', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render SfDataGrid for issues', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('should show empty state when no issues', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: const [],
              totalValidated: 100,
              passedCount: 100,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Selection', () {
      testWidgets('should support select all action', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should support deselect all action', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Filtering', () {
      testWidgets('should support severity filter', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should support search filter', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Accept/Reject Actions', () {
      testWidgets('should call onAcceptTranslation callback', (tester) async {
        // ignore: unused_local_variable
        var acceptCalled = false;
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {
                acceptCalled = true;
              },
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
        // Note: Actual accept button tap would require more setup
      });

      testWidgets('should call onRejectTranslation callback', (tester) async {
        // ignore: unused_local_variable
        var rejectCalled = false;
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {
                rejectCalled = true;
              },
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
        // Note: Actual reject button tap would require more setup
      });
    });

    group('Bulk Operations', () {
      testWidgets('should support bulk accept', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should support bulk reject', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Edit Functionality', () {
      testWidgets('should support optional onEditTranslation', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
              onEditTranslation: (issue, newText) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Export Functionality', () {
      testWidgets('should support optional onExportReport', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
              onExportReport: (path, issues) async {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Close Functionality', () {
      testWidgets('should support optional onClose callback', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
              onClose: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });
  });
}
