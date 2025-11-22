import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'navigation_state_provider.g.dart';

/// Navigation state for session persistence
class NavigationState {
  final String? lastRoute;
  final String? lastProjectId;
  final String? lastModId;

  const NavigationState({
    this.lastRoute,
    this.lastProjectId,
    this.lastModId,
  });

  NavigationState copyWith({
    String? lastRoute,
    String? lastProjectId,
    String? lastModId,
  }) {
    return NavigationState(
      lastRoute: lastRoute ?? this.lastRoute,
      lastProjectId: lastProjectId ?? this.lastProjectId,
      lastModId: lastModId ?? this.lastModId,
    );
  }
}

/// Provider for navigation state with SharedPreferences persistence
@riverpod
class NavigationStateNotifier extends _$NavigationStateNotifier {
  static const String _keyLastRoute = 'navigation_last_route';
  static const String _keyLastProjectId = 'navigation_last_project_id';
  static const String _keyLastModId = 'navigation_last_mod_id';

  @override
  NavigationState build() {
    _loadState();
    return const NavigationState();
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    state = NavigationState(
      lastRoute: prefs.getString(_keyLastRoute),
      lastProjectId: prefs.getString(_keyLastProjectId),
      lastModId: prefs.getString(_keyLastModId),
    );
  }

  Future<void> setLastRoute(String route) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastRoute, route);

    state = state.copyWith(lastRoute: route);
  }

  Future<void> setLastProjectId(String? projectId) async {
    final prefs = await SharedPreferences.getInstance();

    if (projectId == null) {
      await prefs.remove(_keyLastProjectId);
    } else {
      await prefs.setString(_keyLastProjectId, projectId);
    }

    state = state.copyWith(lastProjectId: projectId);
  }

  Future<void> setLastModId(String? modId) async {
    final prefs = await SharedPreferences.getInstance();

    if (modId == null) {
      await prefs.remove(_keyLastModId);
    } else {
      await prefs.setString(_keyLastModId, modId);
    }

    state = state.copyWith(lastModId: modId);
  }

  Future<void> clearLastProject() async {
    await setLastProjectId(null);
  }

  Future<void> clearLastMod() async {
    await setLastModId(null);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyLastRoute);
    await prefs.remove(_keyLastProjectId);
    await prefs.remove(_keyLastModId);

    state = const NavigationState();
  }
}
