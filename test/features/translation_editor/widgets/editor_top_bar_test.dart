import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/translation_editor/providers/editor_selection_notifier.dart';
import 'package:twmt/features/translation_editor/widgets/editor_top_bar.dart';
import 'package:twmt/theme/app_theme.dart';

import '../../../helpers/test_helpers.dart';
import '../../../helpers/test_bootstrap.dart';

EditorTopBar _bar() => EditorTopBar(
      projectId: 'p',
      languageId: 'fr',
      onTranslationSettings: () {},
      onTranslateAll: () {},
      onTranslateSelected: () {},
      onValidate: () {},
      onRescanValidation: () {},
      onExport: () {},
      onImportPack: () {},
    );

void main() {
  const wideTestSize = Size(2400, 1080);

  setUp(() async {
    await TestBootstrap.registerFakes();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = wideTestSize;
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
  });

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('renders 5 visible actions plus Settings icon', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: _bar()),
      theme: AppTheme.atelierDarkTheme,
      screenSize: wideTestSize,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Rules'), findsOneWidget);
    expect(find.text('Selection'), findsOneWidget);
    expect(find.text('Translate all'), findsOneWidget);
    expect(find.text('Validate'), findsOneWidget);
    expect(find.text('Pack'), findsOneWidget);
    expect(find.byTooltip('Translation settings'), findsOneWidget);
  });

  testWidgets('renders the search field with cmdk hint', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: _bar()),
      theme: AppTheme.atelierDarkTheme,
      screenSize: wideTestSize,
    ));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Ctrl+F'), findsOneWidget);
  });

  testWidgets('Selection button is disabled when no selection', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      Scaffold(body: _bar()),
      theme: AppTheme.atelierDarkTheme,
      screenSize: wideTestSize,
      overrides: [
        editorSelectionProvider.overrideWith(() => _StubEmptySelection()),
      ],
    ));
    await tester.pumpAndSettle();

    final selectionFinder = find.ancestor(
      of: find.text('Selection'),
      matching: find.byType(GestureDetector),
    );
    final detector = tester.widget<GestureDetector>(selectionFinder.first);
    expect(detector.onTap, isNull);
  });

  testWidgets('crumb shows project and language and pops on tap', (tester) async {
    final observer = _PopCountingObserver();
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(createThemedTestableWidget(
      Navigator(
        key: navKey,
        observers: [observer],
        onGenerateRoute: (settings) {
          if (settings.name == '/second') {
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => Scaffold(body: _bar()),
            );
          }
          // Root placeholder; '/second' is pushed so the crumb has a route
          // to pop back to.
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: SizedBox.shrink()),
          );
        },
        initialRoute: '/',
      ),
      theme: AppTheme.atelierDarkTheme,
      screenSize: wideTestSize,
    ));
    await tester.pumpAndSettle();

    // Push the editor route so the crumb has somewhere to pop back to.
    navKey.currentState!.pushNamed('/second');
    await tester.pumpAndSettle();

    expect(find.text('Projects'), findsOneWidget);
    await tester.tap(find.text('Projects'));
    await tester.pumpAndSettle();
    expect(observer.popCount, 1);
  });
}

class _StubEmptySelection extends EditorSelection {
  @override
  EditorSelectionState build() => const EditorSelectionState();
}

class _PopCountingObserver extends NavigatorObserver {
  int popCount = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    super.didPop(route, previousRoute);
  }
}
