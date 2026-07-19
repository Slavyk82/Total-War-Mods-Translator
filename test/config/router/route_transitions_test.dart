import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/route_transitions.dart';

/// Builds a real [GoRouterState] (the transitions only read `pageKey`) using
/// the configuration of a throwaway router.
GoRouterState _fakeState() {
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
    ],
  );
  return GoRouterState(
    router.configuration,
    uri: Uri.parse('/test'),
    matchedLocation: '/test',
    fullPath: '/test',
    pathParameters: const {},
    pageKey: const ValueKey<String>('/test'),
  );
}

/// Pumps a bare MaterialApp and returns a live [BuildContext] for invoking
/// transition builders directly.
Future<BuildContext> _pumpContext(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  return tester.element(find.byType(SizedBox));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const child = Text('content', textDirection: TextDirection.ltr);

  group('FluentPageTransitions.fadeTransition', () {
    test('returns a CustomTransitionPage keyed by state.pageKey', () {
      final state = _fakeState();
      final page = FluentPageTransitions.fadeTransition<void>(
        child: child,
        state: state,
      );

      expect(page.key, state.pageKey);
      expect(page.child, same(child));
    });

    test('uses a 150ms duration by default and honors overrides', () {
      final state = _fakeState();

      final defaultPage = FluentPageTransitions.fadeTransition<void>(
        child: child,
        state: state,
      );
      expect(
        defaultPage.transitionDuration,
        const Duration(milliseconds: 150),
      );

      final customPage = FluentPageTransitions.fadeTransition<void>(
        child: child,
        state: state,
        duration: const Duration(milliseconds: 300),
      );
      expect(customPage.transitionDuration, const Duration(milliseconds: 300));
    });

    testWidgets('transitionsBuilder wraps the child in a FadeTransition',
        (tester) async {
      final context = await _pumpContext(tester);
      final page = FluentPageTransitions.fadeTransition<void>(
        child: child,
        state: _fakeState(),
      );

      final atEnd = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(1.0),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      );
      expect(atEnd, isA<FadeTransition>());
      final fadeAtEnd = atEnd as FadeTransition;
      expect(fadeAtEnd.opacity.value, 1.0);
      expect(fadeAtEnd.child, same(child));

      final atStart = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(0.0),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      ) as FadeTransition;
      expect(atStart.opacity.value, 0.0);
    });
  });

  group('FluentPageTransitions.slideFromRightTransition', () {
    test('returns a CustomTransitionPage keyed by state.pageKey with 200ms',
        () {
      final state = _fakeState();
      final page = FluentPageTransitions.slideFromRightTransition<void>(
        child: child,
        state: state,
      );

      expect(page.key, state.pageKey);
      expect(page.child, same(child));
      expect(page.transitionDuration, const Duration(milliseconds: 200));
    });

    test('honors a custom duration', () {
      final page = FluentPageTransitions.slideFromRightTransition<void>(
        child: child,
        state: _fakeState(),
        duration: const Duration(milliseconds: 500),
      );
      expect(page.transitionDuration, const Duration(milliseconds: 500));
    });

    testWidgets('transitionsBuilder combines a fade with a subtle slide',
        (tester) async {
      final context = await _pumpContext(tester);
      final page = FluentPageTransitions.slideFromRightTransition<void>(
        child: child,
        state: _fakeState(),
      );

      // At the start of the animation the page is transparent and offset 30%
      // from the right.
      final atStart = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(0.0),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      );
      expect(atStart, isA<FadeTransition>());
      final startFade = atStart as FadeTransition;
      expect(startFade.opacity.value, 0.0);
      expect(startFade.child, isA<SlideTransition>());
      final startSlide = startFade.child! as SlideTransition;
      expect(startSlide.position.value, const Offset(0.3, 0.0));
      expect(startSlide.child, same(child));

      // At the end it has fully faded in and settled at Offset.zero.
      final atEnd = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(1.0),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      ) as FadeTransition;
      expect(atEnd.opacity.value, 1.0);
      final endSlide = atEnd.child! as SlideTransition;
      expect(endSlide.position.value, Offset.zero);
    });
  });

  group('FluentPageTransitions.noTransition', () {
    testWidgets('has zero duration and returns the child untouched',
        (tester) async {
      final context = await _pumpContext(tester);
      final state = _fakeState();
      final page = FluentPageTransitions.noTransition<void>(
        child: child,
        state: state,
      );

      expect(page.key, state.pageKey);
      expect(page.transitionDuration, Duration.zero);

      final result = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(0.5),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      );
      expect(identical(result, child), isTrue);
    });
  });

  group('FluentPageTransitions.defaultTransition', () {
    testWidgets('uses fade for non-detail views (default)', (tester) async {
      final context = await _pumpContext(tester);
      final page = FluentPageTransitions.defaultTransition<void>(
        child: child,
        state: _fakeState(),
      ) as CustomTransitionPage<void>;

      expect(page.transitionDuration, const Duration(milliseconds: 150));
      final built = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(1.0),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      );
      // Fade only — the child is wrapped directly, no slide involved.
      expect(built, isA<FadeTransition>());
      expect((built as FadeTransition).child, same(child));
    });

    testWidgets('uses slide-from-right for detail views', (tester) async {
      final context = await _pumpContext(tester);
      final page = FluentPageTransitions.defaultTransition<void>(
        child: child,
        state: _fakeState(),
        isDetailView: true,
      ) as CustomTransitionPage<void>;

      expect(page.transitionDuration, const Duration(milliseconds: 200));
      final built = page.transitionsBuilder(
        context,
        const AlwaysStoppedAnimation<double>(0.0),
        const AlwaysStoppedAnimation<double>(0.0),
        child,
      );
      expect(built, isA<FadeTransition>());
      expect((built as FadeTransition).child, isA<SlideTransition>());
    });
  });

  group('in-navigator behavior', () {
    testWidgets('pages animate through the transition when navigating',
        (tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            pageBuilder: (_, state) => FluentPageTransitions.fadeTransition(
              child: const Scaffold(body: Text('page-a')),
              state: state,
            ),
          ),
          GoRoute(
            path: '/detail',
            pageBuilder: (_, state) =>
                FluentPageTransitions.slideFromRightTransition(
              child: const Scaffold(body: Text('page-b')),
              state: state,
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('page-a'), findsOneWidget);

      router.go('/detail');
      await tester.pump();
      // Mid-transition (200ms slide): both the slide and the incoming page
      // are present in the tree.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(SlideTransition), findsWidgets);
      expect(find.text('page-b'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('page-b'), findsOneWidget);
      expect(find.text('page-a'), findsNothing);
    });
  });
}
