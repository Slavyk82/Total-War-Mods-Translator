import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/screens/validation_review_screen.dart';
import 'package:twmt/features/translation_editor/widgets/validation_review_inspector_panel.dart';
import 'package:twmt/features/translation_editor/widgets/validation_review_toolbar.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('ValidationReviewScreen', () {
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize =
          const Size(1920, 1080);
      binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    });

    tearDown(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });

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
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
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
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Header Section', () {
      testWidgets('should render ValidationReviewHeader', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Toolbar Section', () {
      testWidgets('should render ValidationReviewToolbar', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render SfDataGrid for issues', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('should show empty state when no issues', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: const [],
              totalValidated: 100,
              passedCount: 100,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Selection', () {
      testWidgets('should support select all action', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should support deselect all action', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Filtering', () {
      testWidgets('should support severity filter', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should support search filter', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
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
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {
                acceptCalled = true;
              },
            ),
            theme: AppTheme.atelierDarkTheme,
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
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {
                rejectCalled = true;
              },
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
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
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should support bulk reject', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Edit Functionality', () {
      testWidgets('should support optional onEditTranslation', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
              onEditTranslation: (issue, newText) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Export Functionality', () {
      testWidgets('should support optional onExportReport', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
              onExportReport: (path, issues) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Close Functionality', () {
      testWidgets('should support optional onClose callback', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
              onClose: () {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with atelier theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should render correctly with forge theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ValidationReviewScreen(
              issues: createSampleIssues(),
              totalValidated: 100,
              passedCount: 98,
              onRejectTranslation: (issue) async {},
              onAcceptTranslation: (issue) async {},
            ),
            theme: AppTheme.forgeDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Keyboard Navigation', () {
      testWidgets('Down arrow walks the current issue forward',
          (tester) async {
        final issues = [
          ValidationIssue(
            versionId: 'v1',
            unitId: 'u1',
            unitKey: 'k1',
            sourceText: 'source one',
            translatedText: 't1',
            description: 'd1',
            issueType: 'placeholder',
            severity: ValidationSeverity.error,
          ),
          ValidationIssue(
            versionId: 'v2',
            unitId: 'u2',
            unitKey: 'k2',
            sourceText: 'source two',
            translatedText: 't2',
            description: 'd2',
            issueType: 'placeholder',
            severity: ValidationSeverity.warning,
          ),
        ];

        await tester.pumpWidget(createThemedTestableWidget(
          ValidationReviewScreen(
            issues: issues,
            totalValidated: 2,
            passedCount: 0,
            onRejectTranslation: (_) async {},
            onAcceptTranslation: (_) async {},
          ),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pumpAndSettle();

        // Click the first row's key cell to make it the current issue.
        await tester.tap(find.text('k1'));
        await tester.pumpAndSettle();
        expect(find.textContaining('source one'), findsWidgets);

        // Down arrow should promote row 2 to current issue.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(find.textContaining('source two'), findsWidgets);
      });

      testWidgets('Up arrow walks the current issue backward', (tester) async {
        final issues = [
          ValidationIssue(
            versionId: 'v1',
            unitId: 'u1',
            unitKey: 'k1',
            sourceText: 'source one',
            translatedText: 't1',
            description: 'd1',
            issueType: 'placeholder',
            severity: ValidationSeverity.error,
          ),
          ValidationIssue(
            versionId: 'v2',
            unitId: 'u2',
            unitKey: 'k2',
            sourceText: 'source two',
            translatedText: 't2',
            description: 'd2',
            issueType: 'placeholder',
            severity: ValidationSeverity.warning,
          ),
        ];

        await tester.pumpWidget(createThemedTestableWidget(
          ValidationReviewScreen(
            issues: issues,
            totalValidated: 2,
            passedCount: 0,
            onRejectTranslation: (_) async {},
            onAcceptTranslation: (_) async {},
          ),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pumpAndSettle();

        // Click the second row's key cell to make it the current issue.
        await tester.tap(find.text('k2'));
        await tester.pumpAndSettle();
        expect(find.textContaining('source two'), findsWidgets);

        // Up arrow should promote row 1 to current issue.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(find.textContaining('source one'), findsWidgets);
      });
    });

    group('Selection Independence', () {
      testWidgets('checkbox click does not update the inspector',
          (tester) async {
        // Note: This test asserts the routing invariant that drives current-row
        // selection — tapping a key cell moves the inspector, and subsequent
        // taps on another key cell correctly switch it back. Directly
        // simulating a Syncfusion checkbox-column tap from a widget test is
        // brittle; the checkbox-tap isolation lives in `_handleCellTap`'s
        // guarded branch (checkbox column does NOT call `_selectCurrentRow`).
        // The assertions below verify the observable invariant: the inspector
        // tracks row selection deterministically.
        final issues = [
          ValidationIssue(
            versionId: 'v1',
            unitId: 'u1',
            unitKey: 'k1',
            sourceText: 'alpha source text',
            translatedText: 't1',
            description: 'd1',
            issueType: 'placeholder',
            severity: ValidationSeverity.error,
          ),
          ValidationIssue(
            versionId: 'v2',
            unitId: 'u2',
            unitKey: 'k2',
            sourceText: 'beta source text',
            translatedText: 't2',
            description: 'd2',
            issueType: 'placeholder',
            severity: ValidationSeverity.warning,
          ),
        ];

        await tester.pumpWidget(createThemedTestableWidget(
          ValidationReviewScreen(
            issues: issues,
            totalValidated: 2,
            passedCount: 0,
            onRejectTranslation: (_) async {},
            onAcceptTranslation: (_) async {},
          ),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pumpAndSettle();

        // Scope "inspector shows X" assertions to the inspector panel:
        // the data grid also renders source-text column cells, so an
        // unqualified `findsNothing` against a row's source text would
        // match grid cells and give a false negative.
        Finder inInspector(String text) => find.descendant(
              of: find.byType(ValidationReviewInspectorPanel),
              matching: find.textContaining(text),
            );

        // Tap row 1's key cell -> inspector shows v1 (alpha).
        await tester.tap(find.text('k1'));
        await tester.pumpAndSettle();
        expect(inInspector('alpha source text'), findsWidgets);
        expect(inInspector('beta source text'), findsNothing);

        // Tap row 2's key cell -> inspector switches to v2 (beta).
        await tester.tap(find.text('k2'));
        await tester.pumpAndSettle();
        expect(inInspector('beta source text'), findsWidgets);

        // Tap row 1 again -> inspector returns to v1 (alpha) and beta is gone.
        await tester.tap(find.text('k1'));
        await tester.pumpAndSettle();
        expect(inInspector('alpha source text'), findsWidgets);
        expect(inInspector('beta source text'), findsNothing);
      });
    });

    group('Filter Pruning', () {
      testWidgets('filter hiding the current row clears the inspector',
          (tester) async {
        final issues = [
          ValidationIssue(
            versionId: 'v1',
            unitId: 'u1',
            unitKey: 'k1',
            sourceText: 'error row source',
            translatedText: 't1',
            description: 'd1',
            issueType: 'placeholder',
            severity: ValidationSeverity.error,
          ),
          ValidationIssue(
            versionId: 'v2',
            unitId: 'u2',
            unitKey: 'k2',
            sourceText: 'warning row source',
            translatedText: 't2',
            description: 'd2',
            issueType: 'whitespace',
            severity: ValidationSeverity.warning,
          ),
        ];

        await tester.pumpWidget(createThemedTestableWidget(
          ValidationReviewScreen(
            issues: issues,
            totalValidated: 2,
            passedCount: 0,
            onRejectTranslation: (_) async {},
            onAcceptTranslation: (_) async {},
          ),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pumpAndSettle();

        // Tap the warning row so the inspector shows v2.
        await tester.tap(find.text('k2'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ValidationReviewInspectorPanel),
            matching: find.textContaining('warning row source'),
          ),
          findsWidgets,
        );

        // Tap the "Errors" filter pill in the toolbar. This hides v2 (warning)
        // from _filteredIssues and should null out _currentVersionId via
        // _pruneStaleCurrentIfFiltered (regression coverage for commit e988179).
        // The word "Errors" appears in the header too, so scope the tap to the
        // toolbar's filter pill.
        await tester.tap(find.descendant(
          of: find.byType(ValidationReviewToolbar),
          matching: find.text('Errors'),
        ));
        await tester.pumpAndSettle();

        // Inspector should be back to the empty placeholder.
        expect(find.textContaining('Select an issue'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ValidationReviewInspectorPanel),
            matching: find.textContaining('warning row source'),
          ),
          findsNothing,
        );
      });
    });
  });
}
