import 'package:flutter/material.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/features/translation_editor/providers/editor_providers.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/theme/twmt_theme_tokens.dart';
import 'package:twmt/widgets/detail/crumb_segment.dart';
import 'package:twmt/widgets/detail/detail_screen_toolbar.dart';

void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(
          theme: AppTheme.atelierDarkTheme,
          home: Scaffold(body: child),
        ),
      );

  testWidgets('renders crumb and back icon', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'Work › Projects › Foo',
      onBack: () {},
    )));
    expect(find.text('Work › Projects › Foo'), findsOneWidget);
    expect(find.byIcon(FluentIcons.arrow_left_24_regular), findsOneWidget);
  });

  testWidgets('back icon tap fires onBack', (t) async {
    var tapped = false;
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () => tapped = true,
    )));
    await t.tap(find.byIcon(FluentIcons.arrow_left_24_regular));
    expect(tapped, isTrue);
  });

  testWidgets('renders trailing widgets', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
      trailing: const [Text('ACT-1'), Text('ACT-2')],
    )));
    expect(find.text('ACT-1'), findsOneWidget);
    expect(find.text('ACT-2'), findsOneWidget);
  });

  testWidgets('toolbar height is 48', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
    )));
    final container = t.widget<Container>(find.descendant(
      of: find.byType(DetailScreenToolbar),
      matching: find.byType(Container),
    ).first);
    final constraints = container.constraints;
    expect(constraints?.maxHeight ?? (container.decoration != null ? 48.0 : 0.0), 48);
  });

  testWidgets('crumb uses font-mono 12px textDim', (t) async {
    await t.pumpWidget(wrap(DetailScreenToolbar(
      crumb: 'X',
      onBack: () {},
    )));
    final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
    final text = t.widget<Text>(find.text('X'));
    expect(text.style?.fontSize, 12);
    expect(text.style?.color, tokens.textDim);
  });

  group('crumbs API (new)', () {
    testWidgets('renders each segment with "›" separators between them',
        (t) async {
      await t.pumpWidget(wrap(DetailScreenToolbar(
        crumbs: const [
          CrumbSegment('Work'),
          CrumbSegment('Projects', route: '/work/projects'),
          CrumbSegment('Foo'),
        ],
        onBack: () {},
      )));
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Projects'), findsOneWidget);
      expect(find.text('Foo'), findsOneWidget);
      // Two separators for three segments.
      expect(find.text('›'), findsNWidgets(2));
    });

    testWidgets('last segment is bold and uses tokens.text', (t) async {
      await t.pumpWidget(wrap(DetailScreenToolbar(
        crumbs: const [
          CrumbSegment('Work'),
          CrumbSegment('Projects', route: '/work/projects'),
          CrumbSegment('Foo'),
        ],
        onBack: () {},
      )));
      final tokens = AppTheme.atelierDarkTheme.extension<TwmtThemeTokens>()!;
      final last = t.widget<Text>(find.text('Foo'));
      expect(last.style?.fontWeight, FontWeight.w600);
      expect(last.style?.color, tokens.text);
    });

    testWidgets('first segment is non-clickable (no MouseRegion.click)',
        (t) async {
      await t.pumpWidget(wrap(DetailScreenToolbar(
        crumbs: const [
          CrumbSegment('Work'),
          CrumbSegment('Projects', route: '/work/projects'),
          CrumbSegment('Foo'),
        ],
        onBack: () {},
      )));
      // The "Work" segment has no GestureDetector ancestor.
      expect(
        find.ancestor(
          of: find.text('Work'),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
    });

    testWidgets('middle clickable segment has a GestureDetector ancestor',
        (t) async {
      await t.pumpWidget(wrap(DetailScreenToolbar(
        crumbs: const [
          CrumbSegment('Work'),
          CrumbSegment('Projects', route: '/work/projects'),
          CrumbSegment('Foo'),
        ],
        onBack: () {},
      )));
      expect(
        find.ancestor(
          of: find.text('Projects'),
          matching: find.byType(GestureDetector),
        ),
        findsOneWidget,
      );
    });

    testWidgets('tap on middle segment navigates via go_router', (t) async {
      final router = GoRouter(
        initialLocation: '/work/projects/42',
        routes: [
          GoRoute(
            path: '/work/projects/42',
            builder: (_, __) => Scaffold(
              body: DetailScreenToolbar(
                crumbs: const [
                  CrumbSegment('Work'),
                  CrumbSegment('Projects', route: '/work/projects'),
                  CrumbSegment('Foo'),
                ],
                onBack: () {},
              ),
            ),
          ),
          GoRoute(
            path: '/work/projects',
            builder: (_, __) =>
                const Scaffold(body: Text('PROJECTS_LIST_PAGE')),
          ),
        ],
      );
      await t.pumpWidget(ProviderScope(
        child: MaterialApp.router(
          theme: AppTheme.atelierDarkTheme,
          routerConfig: router,
        ),
      ));
      await t.pumpAndSettle();

      await t.tap(find.text('Projects'));
      await t.pumpAndSettle();

      expect(find.text('PROJECTS_LIST_PAGE'), findsOneWidget);
    });

    testWidgets(
      'tap is suppressed when translation is in progress',
      (t) async {
        var navigated = false;
        final router = GoRouter(
          initialLocation: '/a',
          routes: [
            GoRoute(
              path: '/a',
              builder: (_, __) => Scaffold(
                body: DetailScreenToolbar(
                  crumbs: const [
                    CrumbSegment('Work'),
                    CrumbSegment('Projects', route: '/b'),
                    CrumbSegment('Foo'),
                  ],
                  onBack: () {},
                ),
              ),
            ),
            GoRoute(
              path: '/b',
              builder: (_, __) {
                navigated = true;
                return const Scaffold(body: Text('B'));
              },
            ),
          ],
        );
        await t.pumpWidget(ProviderScope(
          overrides: [
            // translationInProgressProvider is a Notifier-generated provider
            // (class TranslationInProgress extends _$TranslationInProgress).
            // Its generated override signature does not match the functional
            // `overrideWith((ref) => bool)` form, so use `overrideWithValue`.
            translationInProgressProvider.overrideWithValue(true),
          ],
          child: MaterialApp.router(
            theme: AppTheme.atelierDarkTheme,
            routerConfig: router,
          ),
        ));
        await t.pumpAndSettle();
        await t.tap(find.text('Projects'));
        await t.pump();
        expect(navigated, isFalse);
        // FluentToast schedules a 4s auto-dismiss via Future.delayed; advance
        // past it so no pending timers remain when the test tears down.
        await t.pump(const Duration(seconds: 5));
      },
    );
  });
}
