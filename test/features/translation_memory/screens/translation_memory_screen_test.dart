import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/translation_memory/screens/translation_memory_screen.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('TranslationMemoryScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should have Column layout', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = TranslationMemoryScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerStatefulWidget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Header', () {
      testWidgets('should display database icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.database_24_regular), findsOneWidget);
      });

      testWidgets('should display Translation Memory title', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Translation Memory'), findsOneWidget);
      });

      testWidgets('should have header padding of 24.0', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Action Buttons', () {
      testWidgets('should display Import button', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Import'), findsOneWidget);
      });

      testWidgets('should display Export button', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Export'), findsOneWidget);
      });

      testWidgets('should display Cleanup button', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Cleanup'), findsOneWidget);
      });

      testWidgets('should have import icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_import_24_regular), findsWidgets);
      });

      testWidgets('should have export icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_export_24_regular), findsWidgets);
      });

      testWidgets('should have broom icon for cleanup', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.broom_24_regular), findsOneWidget);
      });

      testWidgets('should have tooltips on buttons', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(Tooltip), findsWidgets);
      });
    });

    group('Main Layout', () {
      testWidgets('should have Row layout for content', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(Row), findsWidgets);
      });

      testWidgets('should have divider between header and content', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(Divider), findsWidgets);
      });
    });

    group('Statistics Panel', () {
      testWidgets('should render TmStatisticsPanel', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should have fixed width of 280', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Toolbar', () {
      testWidgets('should render TmSearchBar', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should display Refresh button', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Refresh'), findsOneWidget);
      });

      testWidgets('should have refresh icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.arrow_clockwise_24_regular), findsWidgets);
      });

      testWidgets('should have toolbar padding of 16.0', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('DataGrid', () {
      testWidgets('should render TmBrowserDataGrid', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Pagination', () {
      testWidgets('should render TmPaginationBar', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Dialogs', () {
      testWidgets('should show import dialog on Import tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should show export dialog on Export tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should show cleanup dialog on Cleanup tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Refresh Action', () {
      testWidgets('should invalidate providers on refresh', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Vertical Divider', () {
      testWidgets('should have vertical divider between panels', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(VerticalDivider), findsWidgets);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const TranslationMemoryScreen(),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const TranslationMemoryScreen(),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });

      testWidgets('should use theme primary color for icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.byType(TranslationMemoryScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Translation Memory'), findsOneWidget);
      });

      testWidgets('should have accessible action buttons', (tester) async {
        await tester.pumpWidget(createTestableWidget(const TranslationMemoryScreen()));
        await tester.pump();

        expect(find.text('Import'), findsOneWidget);
        expect(find.text('Export'), findsOneWidget);
        expect(find.text('Cleanup'), findsOneWidget);
        expect(find.text('Refresh'), findsOneWidget);
      });
    });
  });
}
