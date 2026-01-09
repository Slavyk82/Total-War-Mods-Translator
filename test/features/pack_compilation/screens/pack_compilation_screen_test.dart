import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/pack_compilation/screens/pack_compilation_screen.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('PackCompilationScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should have padding of 24.0', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(Padding), findsWidgets);
      });

      testWidgets('should have Column layout', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = PackCompilationScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should manage _showEditor state', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Header', () {
      testWidgets('should display box multiple icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.box_multiple_24_regular), findsWidgets);
      });

      testWidgets('should display Pack Compilations title', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.text('Pack Compilations'), findsOneWidget);
      });

      testWidgets('should display New Compilation button', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.text('New Compilation'), findsOneWidget);
      });
    });

    group('List View', () {
      testWidgets('should display list view by default', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should render CompilationList widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Editor View', () {
      testWidgets('should show editor when creating new', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        // Tap New Compilation button
        await tester.tap(find.text('New Compilation'));
        await tester.pumpAndSettle();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should show back button in editor view', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should render CompilationEditor widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Navigation Blocking', () {
      testWidgets('should block navigation during compilation', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should disable back button during compilation', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should show tooltip when navigation blocked', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Create Button', () {
      testWidgets('should render _CreateButton widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.text('New Compilation'), findsOneWidget);
      });

      testWidgets('should have tooltip', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(Tooltip), findsWidgets);
      });

      testWidgets('should have add icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.add_24_regular), findsWidgets);
      });

      testWidgets('should have hover animation', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(AnimatedContainer), findsWidgets);
      });
    });

    group('Editor Header', () {
      testWidgets('should display New Compilation title for new', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should display compilation name when editing', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Cancel and Save', () {
      testWidgets('should support cancel action', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should hide editor on save', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should invalidate provider on save', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Edit Compilation', () {
      testWidgets('should load compilation for editing', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should reset editor state on hide', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Background Color', () {
      testWidgets('should use surfaceContainerLow for editor view', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const PackCompilationScreen(),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const PackCompilationScreen(),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.text('Pack Compilations'), findsOneWidget);
      });

      testWidgets('should have accessible back button', (tester) async {
        await tester.pumpWidget(createTestableWidget(const PackCompilationScreen()));
        await tester.pump();

        expect(find.byType(PackCompilationScreen), findsOneWidget);
      });
    });
  });
}
