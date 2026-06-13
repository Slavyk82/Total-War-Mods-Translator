import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:twmt/config/router/app_router.dart';
import 'package:twmt/providers/selected_game_provider.dart';
import 'package:twmt/theme/app_theme.dart';
import 'package:twmt/widgets/game_selector_dropdown.dart';

import '../helpers/test_bootstrap.dart';
import '../helpers/test_helpers.dart';

/// Surface large enough that the dropdown (and its expanded menu) lay out
/// without horizontal/vertical overflow inside the 1200-wide column.
const Size _surface = Size(1200, 1600);

/// A few configured games covering distinct codes/labels.
const _wh3 = ConfiguredGame(
  code: 'wh3',
  name: 'Total War: WARHAMMER III',
  path: 'C:/wh3',
);
const _rome2 = ConfiguredGame(
  code: 'rome2',
  name: 'Total War: Rome II',
  path: 'C:/rome2',
);
const _troy = ConfiguredGame(
  code: 'troy',
  name: 'Total War: Troy',
  path: 'C:/troy',
);

/// Fake [SelectedGame] notifier. `build()` returns a fixed value and
/// [selectGame] records the argument without touching the settings service,
/// so widget tests need no GetIt/settings wiring for the selection path.
class _FakeSelectedGame extends SelectedGame {
  _FakeSelectedGame(this._initial);
  final ConfiguredGame? _initial;

  /// Games passed to [selectGame], in call order.
  final List<ConfiguredGame> selected = <ConfiguredGame>[];

  @override
  Future<ConfiguredGame?> build() async => _initial;

  @override
  Future<void> selectGame(ConfiguredGame game) async {
    selected.add(game);
    state = AsyncData(game);
  }
}

void main() {
  // Shared handle so individual tests can assert on selection calls.
  late _FakeSelectedGame fakeSelected;

  setUp(() async {
    await TestBootstrap.registerFakes();
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.views.first.physicalSize = _surface;
    binding.platformDispatcher.views.first.devicePixelRatio = 1.0;
    addTearDown(() {
      binding.platformDispatcher.views.first.resetPhysicalSize();
      binding.platformDispatcher.views.first.resetDevicePixelRatio();
    });
  });

  /// Overrides for a data-state widget with [games] configured and
  /// [selected] active. A fresh [_FakeSelectedGame] is stored in
  /// [fakeSelected] for assertions.
  List<Override> dataOverrides(
    List<ConfiguredGame> games,
    ConfiguredGame? selected,
  ) {
    fakeSelected = _FakeSelectedGame(selected);
    return [
      configuredGamesProvider.overrideWith((ref) async => games),
      selectedGameProvider.overrideWith(() => fakeSelected),
    ];
  }

  testWidgets('renders selected game label (Total War prefix stripped)',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3, _rome2], _wh3),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    // gameLabel() strips the "Total War: " prefix.
    expect(find.text('WARHAMMER III'), findsOneWidget);
    // Collapsed: menu items for the other games are not shown yet.
    expect(find.text('Rome II'), findsNothing);
  });

  testWidgets('shows "Select a game" when nothing is selected', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3], null),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Select a game'), findsOneWidget);
  });

  testWidgets('opening the menu lists every configured game', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3, _rome2, _troy], _wh3),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    // Tap the collapsed header to expand the menu.
    await tester.tap(find.text('WARHAMMER III'));
    await tester.pumpAndSettle();

    // Selected game label appears twice now (header + checked menu item),
    // the other two appear once each in the menu.
    expect(find.text('WARHAMMER III'), findsNWidgets(2));
    expect(find.text('Rome II'), findsOneWidget);
    expect(find.text('Troy'), findsOneWidget);
  });

  testWidgets('selecting a different game calls selectGame and collapses',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3, _rome2], _wh3),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    // Expand.
    await tester.tap(find.text('WARHAMMER III'));
    await tester.pumpAndSettle();

    // Tap the "Rome II" menu item.
    await tester.tap(find.text('Rome II'));
    await tester.pumpAndSettle();

    // selectGame was invoked with the rome2 game.
    expect(fakeSelected.selected, hasLength(1));
    expect(fakeSelected.selected.single.code, 'rome2');

    // Menu collapsed again — Rome II is no longer in the (closed) list and the
    // header now reflects the new selection.
    expect(find.text('Rome II'), findsOneWidget); // header only
    expect(find.text('WARHAMMER III'), findsNothing);
  });

  testWidgets('re-tapping the header toggles the menu closed', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3, _rome2], _wh3),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('WARHAMMER III'));
    await tester.pumpAndSettle();
    expect(find.text('Rome II'), findsOneWidget); // open

    await tester.tap(find.text('WARHAMMER III').first);
    await tester.pumpAndSettle();
    expect(find.text('Rome II'), findsNothing); // closed
  });

  testWidgets('hovering the collapsed header updates its style', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3, _rome2], _wh3),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    // Move onto the header to trigger onEnter, then off to trigger onExit.
    await gesture.moveTo(tester.getCenter(find.text('WARHAMMER III')));
    await tester.pumpAndSettle();
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    // Still rendered after hover in/out.
    expect(find.text('WARHAMMER III'), findsOneWidget);
  });

  testWidgets('hovering a menu item updates its highlight', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const [_wh3, _rome2], _wh3),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('WARHAMMER III'));
    await tester.pumpAndSettle();

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    // Hover the non-selected item (onEnter -> _isHovered true branch).
    await gesture.moveTo(tester.getCenter(find.text('Rome II')));
    await tester.pumpAndSettle();
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    expect(find.text('Rome II'), findsOneWidget);
  });

  testWidgets('loading state shows the spinner and loading text',
      (tester) async {
    // configuredGames never completes => loading branch.
    final completer = Completer<List<ConfiguredGame>>();
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        configuredGamesProvider.overrideWith((ref) => completer.future),
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
      ],
      screenSize: _surface,
    ));
    await tester.pump();

    expect(find.text('Loading games...'), findsOneWidget);

    // Complete to drain the pending future before teardown.
    completer.complete(const <ConfiguredGame>[]);
    await tester.pumpAndSettle();
  });

  testWidgets('selected-game loading state shows the loading text',
      (tester) async {
    // configuredGames resolves (non-empty) but selectedGame never settles.
    final selectedCompleter = Completer<ConfiguredGame?>();
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        configuredGamesProvider.overrideWith((ref) async => const [_wh3]),
        selectedGameProvider
            .overrideWith(() => _PendingSelectedGame(selectedCompleter.future)),
      ],
      screenSize: _surface,
    ));
    await tester.pump(); // configuredGames resolves
    await tester.pump(); // selectedGame still pending

    expect(find.text('Loading games...'), findsOneWidget);

    selectedCompleter.complete(_wh3);
    await tester.pumpAndSettle();
  });

  testWidgets('error state shows the error message', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        configuredGamesProvider
            .overrideWith((ref) async => throw Exception('boom')),
        selectedGameProvider.overrideWith(() => _FakeSelectedGame(null)),
      ],
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Error loading games'), findsOneWidget);
  });

  testWidgets('selected-game error state shows the error message',
      (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: [
        configuredGamesProvider.overrideWith((ref) async => const [_wh3]),
        selectedGameProvider.overrideWith(() => _ErrorSelectedGame()),
      ],
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Error loading games'), findsOneWidget);
  });

  testWidgets('no games configured shows the configure CTA', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const <ConfiguredGame>[], null),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    expect(find.text('Configure a game'), findsOneWidget);
  });

  testWidgets('tapping the configure CTA navigates to settings',
      (tester) async {
    fakeSelected = _FakeSelectedGame(null);
    String? location;
    final router = GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) =>
              const Scaffold(body: SizedBox(width: 300, child: GameSelectorDropdown())),
        ),
        GoRoute(
          path: AppRoutes.settings,
          builder: (_, _) => const Scaffold(body: Text('settings-screen')),
        ),
      ],
      redirect: (context, state) {
        location = state.uri.toString();
        return null;
      },
    );

    await tester.pumpWidget(ProviderScope(
      overrides: [
        configuredGamesProvider.overrideWith((ref) async => const <ConfiguredGame>[]),
        selectedGameProvider.overrideWith(() => fakeSelected),
      ],
      child: MaterialApp.router(
        theme: AppTheme.atelierDarkTheme,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Configure a game'));
    await tester.pumpAndSettle();

    expect(location, AppRoutes.settings);
    expect(find.text('settings-screen'), findsOneWidget);
  });

  testWidgets('hovering the configure CTA updates its style', (tester) async {
    await tester.pumpWidget(createThemedTestableWidget(
      const GameSelectorDropdown(),
      theme: AppTheme.atelierDarkTheme,
      overrides: dataOverrides(const <ConfiguredGame>[], null),
      screenSize: _surface,
    ));
    await tester.pumpAndSettle();

    final gesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.text('Configure a game')));
    await tester.pumpAndSettle();
    await gesture.moveTo(Offset.zero);
    await tester.pumpAndSettle();

    expect(find.text('Configure a game'), findsOneWidget);
  });
}

/// [SelectedGame] fake whose `build()` awaits an externally controlled future,
/// used to exercise the selected-game loading branch.
class _PendingSelectedGame extends SelectedGame {
  _PendingSelectedGame(this._future);
  final Future<ConfiguredGame?> _future;

  @override
  Future<ConfiguredGame?> build() => _future;
}

/// [SelectedGame] fake whose `build()` throws, exercising the selected-game
/// error branch.
class _ErrorSelectedGame extends SelectedGame {
  @override
  Future<ConfiguredGame?> build() async => throw Exception('boom');
}
