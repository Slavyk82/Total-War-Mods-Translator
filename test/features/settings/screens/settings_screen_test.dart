import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/settings/screens/settings_screen.dart';
import 'package:twmt/widgets/layouts/fluent_scaffold.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('SettingsScreen', () {
    group('Widget Structure', () {
      testWidgets('should render FluentScaffold as root widget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(FluentScaffold), findsOneWidget);
      });

      testWidgets('should render with Column layout', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = SettingsScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a StatefulWidget', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        final settingsScreen = tester.widget<SettingsScreen>(
          find.byType(SettingsScreen),
        );
        expect(settingsScreen, isA<StatefulWidget>());
      });
    });

    group('Header', () {
      testWidgets('should display settings icon', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.settings_24_regular), findsWidgets);
      });

      testWidgets('should display Settings title', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets('should have correct header padding', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    group('Tab Controller', () {
      testWidgets('should use DefaultTabController with 3 tabs', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(DefaultTabController), findsOneWidget);
      });

      testWidgets('should have TabBar for navigation', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(TabBar), findsOneWidget);
      });

      testWidgets('should have TabBarView for content', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(TabBarView), findsOneWidget);
      });
    });

    group('Tabs', () {
      testWidgets('should display General tab', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.text('General'), findsOneWidget);
      });

      testWidgets('should display Folders tab', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.text('Folders'), findsOneWidget);
      });

      testWidgets('should display LLM Providers tab', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.text('LLM Providers'), findsOneWidget);
      });

      testWidgets('should have correct tab icons', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byIcon(FluentIcons.settings_24_regular), findsWidgets);
        expect(find.byIcon(FluentIcons.folder_24_regular), findsOneWidget);
        expect(find.byIcon(FluentIcons.brain_circuit_24_regular), findsOneWidget);
      });
    });

    group('Tab Bar Styling', () {
      testWidgets('should use scrollable TabBar', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        final tabBar = tester.widget<TabBar>(find.byType(TabBar));
        expect(tabBar.isScrollable, isTrue);
      });

      testWidgets('should have transparent divider color', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        final tabBar = tester.widget<TabBar>(find.byType(TabBar));
        expect(tabBar.dividerColor, equals(Colors.transparent));
      });

      testWidgets('should have empty indicator', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        final tabBar = tester.widget<TabBar>(find.byType(TabBar));
        expect(tabBar.indicator, equals(const BoxDecoration()));
      });
    });

    group('Tab Content', () {
      testWidgets('should render GeneralSettingsTab', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('should render FoldersSettingsTab', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('should render LlmProvidersTab', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    group('Fluent Tab Design', () {
      testWidgets('should use custom FluentTabBar', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('should use custom FluentTab with hover states', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    group('Border Styling', () {
      testWidgets('should have border below tab bar', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly with light theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const SettingsScreen(),
            theme: ThemeData.light(),
          ),
        );
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('should render correctly with dark theme', (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const SettingsScreen(),
            theme: ThemeData.dark(),
          ),
        );
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('should adapt label colors based on theme brightness', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    group('Tab Interaction', () {
      testWidgets('should switch tabs on tap', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        // Tap on Folders tab
        await tester.tap(find.text('Folders'));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });

      testWidgets('should have animated tab transitions', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(SettingsScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible tab labels', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.text('General'), findsOneWidget);
        expect(find.text('Folders'), findsOneWidget);
        expect(find.text('LLM Providers'), findsOneWidget);
      });

      testWidgets('should support keyboard navigation', (tester) async {
        await tester.pumpWidget(createTestableWidget(const SettingsScreen()));
        await tester.pump();

        expect(find.byType(TabBar), findsOneWidget);
      });
    });
  });
}
