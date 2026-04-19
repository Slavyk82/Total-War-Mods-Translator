import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/widgets/validation_review_inspector_panel.dart';
import 'package:twmt/providers/batch/batch_operations_provider.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';

void main() {
  setUp(() async {
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

  testWidgets('shows empty state when no issue is current', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: ValidationReviewInspectorPanel(
          currentIssue: null,
          currentIndex: null,
          total: 0,
          isProcessing: false,
          onEdit: () {},
          onAccept: () {},
          onReject: () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('Select an issue'), findsOneWidget);
  });

  testWidgets('renders key, source and translation for the current issue',
      (tester) async {
    final issue = ValidationIssue(
      versionId: 'v1',
      unitId: 'u1',
      unitKey: 'agent_actions_localised_description',
      sourceText: "Use the Skald's Knowledge to increase morale.",
      translatedText: 'Utilise le Savoir du Skald.',
      description: 'Placeholder mismatch',
      issueType: 'placeholder',
      severity: ValidationSeverity.error,
    );

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: ValidationReviewInspectorPanel(
          currentIssue: issue,
          currentIndex: 1,
          total: 5,
          isProcessing: false,
          onEdit: () {},
          onAccept: () {},
          onReject: () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('agent_actions_localised_description'),
        findsOneWidget);
    expect(find.textContaining("Use the Skald's Knowledge"), findsOneWidget);
    expect(find.textContaining('Utilise le Savoir du Skald'), findsOneWidget);
    expect(find.textContaining('1 / 5'), findsOneWidget);
  });

  testWidgets('renders a spinner while the issue is processing',
      (tester) async {
    final issue = ValidationIssue(
      versionId: 'v1',
      unitId: 'u1',
      unitKey: 'k',
      sourceText: 's',
      translatedText: 't',
      description: 'd',
      issueType: 'placeholder',
      severity: ValidationSeverity.error,
    );

    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(
        body: ValidationReviewInspectorPanel(
          currentIssue: issue,
          currentIndex: 1,
          total: 1,
          isProcessing: true,
          onEdit: () {},
          onAccept: () {},
          onReject: () {},
        ),
      ),
      theme: AppTheme.atelierDarkTheme,
    ));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
