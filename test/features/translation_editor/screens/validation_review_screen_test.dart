import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/features/translation_editor/screens/validation_review_screen.dart';
import 'package:twmt/features/translation_editor/widgets/validation_review_inspector_panel.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';
import 'package:twmt/widgets/lists/filter_toolbar.dart';
import '../../../helpers/test_helpers.dart';

const _testProjectId = 'test-project-vr';
const _testLanguageId = 'test-language-vr';

List<Override> _screenOverrides() => [
      currentProjectProvider(_testProjectId).overrideWith(
        (ref) async => Project(
          id: _testProjectId,
          name: 'Test Project',
          gameInstallationId: 'gi-1',
          projectType: 'mod',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      ),
      currentLanguageProvider(_testLanguageId).overrideWith(
        (ref) async => const Language(
          id: _testLanguageId,
          code: 'es',
          name: 'Spanish',
          nativeName: 'Espanol',
        ),
      ),
    ];

Widget _buildScreen({
  required List<ValidationIssue> issues,
  int totalValidated = 100,
  int passedCount = 98,
  Future<void> Function(ValidationIssue)? onAccept,
  Future<void> Function(ValidationIssue)? onReject,
  Future<void> Function(ValidationIssue, String)? onEdit,
  Future<void> Function(String, List<ValidationIssue>)? onExport,
  VoidCallback? onClose,
  ThemeData? theme,
}) {
  return createThemedTestableWidget(
    ValidationReviewScreen(
      projectId: _testProjectId,
      languageId: _testLanguageId,
      issues: issues,
      totalValidated: totalValidated,
      passedCount: passedCount,
      onRejectTranslation: onReject ?? (_) async {},
      onAcceptTranslation: onAccept ?? (_) async {},
      onEditTranslation: onEdit,
      onExportReport: onExport,
      onClose: onClose,
    ),
    theme: theme ?? AppTheme.atelierDarkTheme,
    overrides: _screenOverrides(),
  );
}

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
          translatedText: 'Chaine de test',
          description: 'Trailing whitespace',
          issueType: 'whitespace',
          severity: ValidationSeverity.warning,
        ),
      ];
    }

    group('Widget Structure', () {
      testWidgets('should render Material as root widget', (tester) async {
        await tester
            .pumpWidget(_buildScreen(issues: createSampleIssues()));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
        expect(find.byType(Material), findsWidgets);
      });

      testWidgets('should accept required parameters', (tester) async {
        final issues = createSampleIssues();
        final screen = ValidationReviewScreen(
          projectId: _testProjectId,
          languageId: _testLanguageId,
          issues: issues,
          totalValidated: 100,
          passedCount: 98,
          onRejectTranslation: (issue) async {},
          onAcceptTranslation: (issue) async {},
        );
        expect(screen.issues, equals(issues));
        expect(screen.totalValidated, equals(100));
        expect(screen.passedCount, equals(98));
        expect(screen.projectId, equals(_testProjectId));
        expect(screen.languageId, equals(_testLanguageId));
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester
            .pumpWidget(_buildScreen(issues: createSampleIssues()));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Navigation', () {
      testWidgets('renders DetailScreenToolbar with the Validation Review crumb',
          (tester) async {
        await tester
            .pumpWidget(_buildScreen(issues: createSampleIssues()));
        await tester.pumpAndSettle();

        expect(find.byType(DetailScreenToolbar), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(DetailScreenToolbar),
            matching: find.text('Validation Review'),
          ),
          findsOneWidget,
        );
      });
    });

    group('Filter Toolbar', () {
      testWidgets('renders FilterToolbar with the SEVERITY pill group',
          (tester) async {
        await tester
            .pumpWidget(_buildScreen(issues: createSampleIssues()));
        await tester.pumpAndSettle();

        expect(find.byType(FilterToolbar), findsOneWidget);
        expect(find.text('SEVERITY'), findsOneWidget);
        expect(find.text('Errors'), findsOneWidget);
        expect(find.text('Warnings'), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render issues in the grid', (tester) async {
        await tester
            .pumpWidget(_buildScreen(issues: createSampleIssues()));
        await tester.pumpAndSettle();

        expect(find.text('key1'), findsOneWidget);
        expect(find.text('key2'), findsOneWidget);
      });
    });

    group('Empty State', () {
      testWidgets('should show empty state when no issues', (tester) async {
        await tester.pumpWidget(_buildScreen(
          issues: const [],
          totalValidated: 100,
          passedCount: 100,
        ));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('All issues have been reviewed'),
          findsOneWidget,
        );
      });
    });

    group('Accept/Reject Actions', () {
      testWidgets('should accept onAcceptTranslation callback', (tester) async {
        var acceptCalled = false;
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          onAccept: (_) async {
            acceptCalled = true;
          },
        ));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
        expect(acceptCalled, isFalse);
      });

      testWidgets('should accept onRejectTranslation callback', (tester) async {
        var rejectCalled = false;
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          onReject: (_) async {
            rejectCalled = true;
          },
        ));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
        expect(rejectCalled, isFalse);
      });
    });

    group('Edit Functionality', () {
      testWidgets('should accept optional onEditTranslation', (tester) async {
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          onEdit: (issue, newText) async {},
        ));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Export Functionality', () {
      testWidgets('should accept optional onExportReport', (tester) async {
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          onExport: (path, issues) async {},
        ));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Close Functionality', () {
      testWidgets('should accept optional onClose callback', (tester) async {
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          onClose: () {},
        ));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with atelier theme', (tester) async {
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        expect(find.byType(ValidationReviewScreen), findsOneWidget);
      });

      testWidgets('should render correctly with forge theme', (tester) async {
        await tester.pumpWidget(_buildScreen(
          issues: createSampleIssues(),
          theme: AppTheme.forgeDarkTheme,
        ));
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

        await tester.pumpWidget(_buildScreen(
          issues: issues,
          totalValidated: 2,
          passedCount: 0,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('k1'));
        await tester.pumpAndSettle();
        expect(find.textContaining('source one'), findsWidgets);

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

        await tester.pumpWidget(_buildScreen(
          issues: issues,
          totalValidated: 2,
          passedCount: 0,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('k2'));
        await tester.pumpAndSettle();
        expect(find.textContaining('source two'), findsWidgets);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(find.textContaining('source one'), findsWidgets);
      });
    });

    group('Selection Independence', () {
      testWidgets('clicking a row single-selects it and updates the inspector',
          (tester) async {
        // Under the unified selection model, a non-checkbox cell tap clears
        // the bulk selection and single-selects the row, and the inspector
        // reflects the single selection. The assertions below verify the
        // observable invariant: the inspector tracks single-selection
        // deterministically.
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

        await tester.pumpWidget(_buildScreen(
          issues: issues,
          totalValidated: 2,
          passedCount: 0,
        ));
        await tester.pumpAndSettle();

        Finder inInspector(String text) => find.descendant(
              of: find.byType(ValidationReviewInspectorPanel),
              matching: find.textContaining(text),
            );

        await tester.tap(find.text('k1'));
        await tester.pumpAndSettle();
        expect(inInspector('alpha source text'), findsWidgets);
        expect(inInspector('beta source text'), findsNothing);

        await tester.tap(find.text('k2'));
        await tester.pumpAndSettle();
        expect(inInspector('beta source text'), findsWidgets);

        await tester.tap(find.text('k1'));
        await tester.pumpAndSettle();
        expect(inInspector('alpha source text'), findsWidgets);
        expect(inInspector('beta source text'), findsNothing);
      });
    });

    group('Shortcuts', () {
      testWidgets('Ctrl+A toggles select-all for filtered issues',
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

        await tester.pumpWidget(_buildScreen(
          issues: issues,
          totalValidated: 2,
          passedCount: 0,
        ));
        await tester.pumpAndSettle();

        expect(find.textContaining('Select an issue'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(find.textContaining('2 issues selected'), findsOneWidget);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pumpAndSettle();

        expect(find.textContaining('Select an issue'), findsOneWidget);
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

        await tester.pumpWidget(_buildScreen(
          issues: issues,
          totalValidated: 2,
          passedCount: 0,
        ));
        await tester.pumpAndSettle();

        await tester.tap(find.text('k2'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byType(ValidationReviewInspectorPanel),
            matching: find.textContaining('warning row source'),
          ),
          findsWidgets,
        );

        // Tap the "Errors" SEVERITY pill in the FilterToolbar. Scope the
        // search to the FilterToolbar so "Errors" matches the pill and not
        // any inspector or status-bar text that might share the word.
        await tester.tap(find.descendant(
          of: find.byType(FilterToolbar),
          matching: find.text('Errors'),
        ));
        await tester.pumpAndSettle();

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
