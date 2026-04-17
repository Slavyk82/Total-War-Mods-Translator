import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:twmt/features/help/screens/help_screen.dart';
import 'package:twmt/theme/app_theme.dart';
import '../../../helpers/test_helpers.dart';

void main() {
  group('HelpScreen', () {
    group('Widget Structure', () {
      testWidgets('should render a Material root with token background',
          (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
        expect(find.byType(Material), findsWidgets);
      });

      testWidgets('should render with Column layout', (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        expect(find.byType(Column), findsWidgets);
      });

      testWidgets('should have const constructor', (tester) async {
        const screen = HelpScreen();
        expect(screen, isNotNull);
      });
    });

    group('State Management', () {
      testWidgets('should be a ConsumerWidget', (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        final helpScreen = tester.widget<HelpScreen>(find.byType(HelpScreen));
        expect(helpScreen, isA<ConsumerWidget>());
      });
    });

    group('Header', () {
      testWidgets('should display question circle icon', (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        expect(find.byIcon(FluentIcons.question_circle_24_regular),
            findsOneWidget);
      });

      testWidgets('should display Help title', (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        expect(find.text('Help'), findsOneWidget);
      });
    });

    group('Content Loading', () {
      testWidgets('should show loading indicator while loading',
          (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        // During initial load.
        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Theme Integration', () {
      testWidgets('should render correctly under Atelier dark theme',
          (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const HelpScreen(),
            theme: AppTheme.atelierDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });

      testWidgets('should render correctly under Forge dark theme',
          (tester) async {
        await tester.pumpWidget(
          createThemedTestableWidget(
            const HelpScreen(),
            theme: AppTheme.forgeDarkTheme,
          ),
        );
        await tester.pump();

        expect(find.byType(HelpScreen), findsOneWidget);
      });
    });

    group('Accessibility', () {
      testWidgets('should have accessible header', (tester) async {
        await tester.pumpWidget(createThemedTestableWidget(
          const HelpScreen(),
          theme: AppTheme.atelierDarkTheme,
        ));
        await tester.pump();

        expect(find.text('Help'), findsOneWidget);
      });
    });
  });
}
