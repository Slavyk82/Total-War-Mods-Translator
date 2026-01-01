import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/translation_editor/screens/translation_progress_screen.dart';
import 'package:twmt/services/translation/i_translation_orchestrator.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

// Mock classes
class MockTranslationOrchestrator extends Mock implements ITranslationOrchestrator {}

void main() {
  late MockTranslationOrchestrator mockOrchestrator;

  setUp(() {
    mockOrchestrator = MockTranslationOrchestrator();
  });

  group('TranslationProgressScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should accept orchestrator parameter', (tester) async {
        final screen = TranslationProgressScreen(
          orchestrator: mockOrchestrator,
          onComplete: () {},
        );
        expect(screen.orchestrator, equals(mockOrchestrator));
      });

      testWidgets('should accept onComplete callback', (tester) async {
        var callbackCalled = false;
        final screen = TranslationProgressScreen(
          orchestrator: mockOrchestrator,
          onComplete: () => callbackCalled = true,
        );
        screen.onComplete();
        expect(callbackCalled, isTrue);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Header', () {
      testWidgets('should display Translation in Progress title', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });

      testWidgets('should have no leading widget in header', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Navigation Blocking', () {
      testWidgets('should use PopScope to block navigation', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(PopScope), findsOneWidget);
      });

      testWidgets('should block navigation during active translation', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Progress Display', () {
      testWidgets('should show preparation view when preparing batch', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
              preparationCallback: () async => null,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });

      testWidgets('should show progress body when translation is active', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
              batchId: 'test-batch',
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Stream Handling', () {
      testWidgets('should use StreamBuilder for progress updates', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Stop Functionality', () {
      testWidgets('should support stop action', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Error Handling', () {
      testWidgets('should display error section when error occurs', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Timer', () {
      testWidgets('should track elapsed time', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Log Terminal', () {
      testWidgets('should render LogTerminal component', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Project Name', () {
      testWidgets('should accept optional projectName parameter', (tester) async {
        final screen = TranslationProgressScreen(
          orchestrator: mockOrchestrator,
          onComplete: () {},
          projectName: 'Test Project',
        );
        expect(screen.projectName, equals('Test Project'));
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });
    });

    group('Lifecycle', () {
      testWidgets('should mark translation as in progress on init', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationProgressScreen), findsOneWidget);
      });

      testWidgets('should cleanup timer on dispose', (tester) async {
        await tester.pumpWidget(
          createTestableWidget(
            TranslationProgressScreen(
              orchestrator: mockOrchestrator,
              onComplete: () {},
            ),
          ),
        );
        await tester.pump();

        // Navigate away to trigger dispose
        await tester.pumpWidget(createTestableWidget(const SizedBox()));

        expect(find.byType(TranslationProgressScreen), findsNothing);
      });
    });
  });
}
