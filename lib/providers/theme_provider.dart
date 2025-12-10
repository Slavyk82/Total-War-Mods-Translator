import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_provider.g.dart';

/// Theme notifier using AsyncNotifier to properly handle async initialization
///
/// Supports three modes: system (synced with Windows), light, and dark.
/// Default is system mode to respect user's Windows preferences.
@riverpod
class ThemeNotifier extends _$ThemeNotifier {
  static const String _themeModeKey = 'theme_mode';

  @override
  Future<ThemeMode> build() async {
    // Load theme from SharedPreferences before returning
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);

    if (savedMode != null) {
      return _stringToThemeMode(savedMode);
    }

    // Default to system mode to sync with Windows theme
    return ThemeMode.system;
  }

  /// Convert string to ThemeMode
  ThemeMode _stringToThemeMode(String value) {
    switch (value) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  /// Convert ThemeMode to string for storage
  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  /// Cycle through theme modes: system -> light -> dark -> system
  Future<void> cycleTheme() async {
    final currentMode = await future;
    final ThemeMode newMode;

    switch (currentMode) {
      case ThemeMode.system:
        newMode = ThemeMode.light;
      case ThemeMode.light:
        newMode = ThemeMode.dark;
      case ThemeMode.dark:
        newMode = ThemeMode.system;
    }

    await setThemeMode(newMode);
  }

  /// Set theme mode explicitly
  Future<void> setThemeMode(ThemeMode mode) async {
    final currentMode = await future;
    if (currentMode == mode) return;

    // Update state optimistically
    state = AsyncValue.data(mode);

    // Persist to storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _themeModeToString(mode));
  }
}
