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
}
