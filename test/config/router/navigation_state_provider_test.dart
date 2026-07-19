import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/config/router/navigation_state_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavigationState.copyWith', () {
    test('leaves fields unchanged when arguments are omitted', () {
      const state = NavigationState(
        lastRoute: '/route',
        lastProjectId: 'p1',
        lastModId: 'm1',
      );

      final copy = state.copyWith();

      expect(copy.lastRoute, '/route');
      expect(copy.lastProjectId, 'p1');
      expect(copy.lastModId, 'm1');
    });

    test('clears a field when passed a () => null getter', () {
      const state = NavigationState(
        lastRoute: '/route',
        lastProjectId: 'p1',
        lastModId: 'm1',
      );

      final copy = state.copyWith(lastProjectId: () => null);

      expect(copy.lastProjectId, isNull);
      // Other fields untouched.
      expect(copy.lastRoute, '/route');
      expect(copy.lastModId, 'm1');
    });
  });

  group('NavigationStateNotifier in-memory clearing', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        'navigation_last_route': '/editor',
        'navigation_last_project_id': 'project-1',
        'navigation_last_mod_id': 'mod-1',
      });
      container = ProviderContainer();
    });

    tearDown(() => container.dispose());

    Future<void> waitForLoad() async {
      // Keep an active listener so the autoDispose provider stays mounted for
      // the duration of the test.
      container.listen<NavigationState>(navigationStateProvider, (_, _) {});
      final notifier = container.read(navigationStateProvider.notifier);
      // build() kicks off _loadState() asynchronously; let it settle so the
      // in-memory state reflects the mocked SharedPreferences values.
      await Future<void>.delayed(Duration.zero);
      // Sanity: state is populated from prefs.
      expect(notifier.state.lastProjectId, 'project-1');
      expect(notifier.state.lastModId, 'mod-1');
    }

    test('setLastProjectId(null) nulls the in-memory state', () async {
      await waitForLoad();
      final notifier = container.read(navigationStateProvider.notifier);

      await notifier.setLastProjectId(null);

      expect(notifier.state.lastProjectId, isNull,
          reason: 'in-memory state must clear, not retain the old value');
    });

    test('clearLastProject() nulls the in-memory state', () async {
      await waitForLoad();
      final notifier = container.read(navigationStateProvider.notifier);

      await notifier.clearLastProject();

      expect(notifier.state.lastProjectId, isNull);
    });

    test('clearLastMod() nulls the in-memory state', () async {
      await waitForLoad();
      final notifier = container.read(navigationStateProvider.notifier);

      await notifier.clearLastMod();

      expect(notifier.state.lastModId, isNull);
    });
  });

  group('NavigationStateNotifier persistence', () {
    late ProviderContainer container;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      container = ProviderContainer();
      // Keep an active listener so the autoDispose provider stays mounted for
      // the duration of the test.
      container.listen<NavigationState>(navigationStateProvider, (_, _) {});
    });

    tearDown(() => container.dispose());

    /// Lets the async _loadState() kicked off by build() settle before the
    /// test mutates state, so the load cannot clobber later writes.
    Future<NavigationStateNotifier> loadedNotifier() async {
      final notifier = container.read(navigationStateProvider.notifier);
      await Future<void>.delayed(Duration.zero);
      return notifier;
    }

    test('build() with empty prefs leaves all fields null', () async {
      final notifier = await loadedNotifier();

      expect(notifier.state.lastRoute, isNull);
      expect(notifier.state.lastProjectId, isNull);
      expect(notifier.state.lastModId, isNull);
    });

    test('setLastRoute updates state and persists to prefs', () async {
      final notifier = await loadedNotifier();

      await notifier.setLastRoute('/work/projects');

      expect(notifier.state.lastRoute, '/work/projects');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('navigation_last_route'), '/work/projects');
    });

    test('setLastProjectId persists a value and removes it on null', () async {
      final notifier = await loadedNotifier();
      final prefs = await SharedPreferences.getInstance();

      await notifier.setLastProjectId('project-9');
      expect(notifier.state.lastProjectId, 'project-9');
      expect(prefs.getString('navigation_last_project_id'), 'project-9');

      await notifier.setLastProjectId(null);
      expect(notifier.state.lastProjectId, isNull);
      expect(prefs.getString('navigation_last_project_id'), isNull);
    });

    test('setLastModId persists a value and removes it on null', () async {
      final notifier = await loadedNotifier();
      final prefs = await SharedPreferences.getInstance();

      await notifier.setLastModId('mod-9');
      expect(notifier.state.lastModId, 'mod-9');
      expect(prefs.getString('navigation_last_mod_id'), 'mod-9');

      await notifier.setLastModId(null);
      expect(notifier.state.lastModId, isNull);
      expect(prefs.getString('navigation_last_mod_id'), isNull);
    });

    test('clearAll wipes both the in-memory state and prefs', () async {
      final notifier = await loadedNotifier();
      await notifier.setLastRoute('/somewhere');
      await notifier.setLastProjectId('p1');
      await notifier.setLastModId('m1');

      await notifier.clearAll();

      expect(notifier.state.lastRoute, isNull);
      expect(notifier.state.lastProjectId, isNull);
      expect(notifier.state.lastModId, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('navigation_last_route'), isNull);
      expect(prefs.getString('navigation_last_project_id'), isNull);
      expect(prefs.getString('navigation_last_mod_id'), isNull);
    });
  });

  group('navigationStateProvider overrides', () {
    test('overrideWithValue serves the fixed state', () {
      final container = ProviderContainer(
        overrides: [
          navigationStateProvider.overrideWithValue(
            const NavigationState(lastRoute: '/overridden'),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(navigationStateProvider).lastRoute, '/overridden');
    });
  });
}
