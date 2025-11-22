import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_provider.g.dart';

/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// This prevents the race condition where the UI displays with the default
/// theme before the saved theme is loaded from SharedPreferences.
@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  static const String _themeModeKey = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    // Load theme from SharedPreferences before returning
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);

    if (savedMode != null) {
      return savedMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
    }

    return ThemeMode.light;
  }

  /// Check if current theme is dark mode
  /// Returns false while loading
  bool get isDarkMode {
    final currentState = state;
    return currentState.maybeWhen(
      data: (mode) => mode == ThemeMode.dark,
      orElse: () => false,
    );
  }

  /// Toggle between light and dark themes
  Future<void> toggleTheme() async {
    final currentMode = await future;
    final newMode = currentMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;

    // Update state optimistically
    state = AsyncValue.data(newMode);

    // Persist to storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, newMode == ThemeMode.dark ? 'dark' : 'light');
  }

  /// Set theme mode explicitly
  Future<void> setThemeMode(ThemeMode mode) async {
    final currentMode = await future;
    if (currentMode == mode) return;

    // Update state optimistically
    state = AsyncValue.data(mode);

    // Persist to storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode == ThemeMode.dark ? 'dark' : 'light');
  }
}
