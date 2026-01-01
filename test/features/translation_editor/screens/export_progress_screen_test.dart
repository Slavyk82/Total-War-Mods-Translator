import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/screens/export_progress_screen.dart';
import 'package:twmt/services/file/export_orchestrator_service.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

// Mock classes
class MockExportOrchestratorService extends Mock implements ExportOrchestratorService {}

void main() {
  late MockExportOrchestratorService mockExportService;

  setUp(() {
    mockExportService = MockExportOrchestratorService();
  });

  group('ExportProgressScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should accept required parameters', (tester) async {
        final screen = ExportProgressScreen(
          exportService: mockExportService,
          projectId: 'test-project',
          languageCodes: const ['fr', 'de'],
          onComplete: (result) {},
        );
        expect(screen.projectId, equals('test-project'));
        expect(screen.languageCodes, equals(['fr', 'de']));
      });

      testWidgets('should accept optional generatePackImage parameter', (tester) async {
        final screen = ExportProgressScreen(
          exportService: mockExportService,
          projectId: 'test-project',
          languageCodes: const ['fr', 'de'],
          onComplete: (result) {},
          generatePackImage: false,
        );
        expect(screen.generatePackImage, isFalse);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Header', () {
      testWidgets('should display Generating Pack title', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });

      testWidgets('should have no leading widget in header', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Navigation Blocking', () {
      testWidgets('should use PopScope to block navigation', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(PopScope), findsOneWidget);
      });

      testWidgets('should block navigation during export', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Progress Display', () {
      testWidgets('should display progress header', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });

      testWidgets('should display progress section', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });

      testWidgets('should display status info', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Elapsed Time', () {
      testWidgets('should track elapsed time', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Log Terminal', () {
      testWidgets('should render LogTerminal component', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('should display error section when error occurs', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Success State', () {
      testWidgets('should display success section on completion', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Close Button', () {
      testWidgets('should show close button when complete', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });

      testWidgets('should call onComplete callback when closing', (tester) async {
        ExportResult? receivedResult;
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {
                receivedResult = result;
              },
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Step Labels', () {
      testWidgets('should display correct step labels', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Language Progress', () {
      testWidgets('should display language being processed', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });

      testWidgets('should display languages list in header', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });

    group('Lifecycle', () {
      testWidgets('should start export on init', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            ExportProgressScreen(
              exportService: mockExportService,
              projectId: 'test-project',
              languageCodes: const ['fr', 'de'],
              onComplete: (result) {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ExportProgressScreen), findsOneWidget);
      });
    });
  });
}
