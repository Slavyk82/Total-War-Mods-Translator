import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_name_provider.g.dart';

/// Identifies which TWMT palette/typography couple is active.
///
/// Only affects the dark theme for now — light theme is deferred to a
/// later plan (see spec §11, scope).
enum TwmtThemeName {
  atelier,
  forge;

  static TwmtThemeName? fromString(String? value) {
    switch (value) {
      case 'atelier':
        return TwmtThemeName.atelier;
      case 'forge':
        return TwmtThemeName.forge;
      default:
        return null;
    }
  }

  String get storageKey => name;
}

/// Persisted Riverpod notifier carrying the user's palette choice.
///
/// Storage key: `twmt_theme_name`. Default: [TwmtThemeName.atelier].
@riverpod
class ThemeNameNotifier extends _$ThemeNameNotifier {
  static const String _prefsKey = 'twmt_theme_name';

  @override
  Future<TwmtThemeName> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    return TwmtThemeName.fromString(raw) ?? TwmtThemeName.atelier;
  }

  /// Switch the active palette and persist the new value.
  ///
  /// No-ops when the caller requests the already-active value.
  Future<void> setThemeName(TwmtThemeName name) async {
    final current = await future;
    if (current == name) return;

    state = AsyncValue.data(name);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, name.storageKey);
  }

  /// Cycle through the available palettes: atelier -> forge -> atelier.
  Future<void> cycleTheme() async {
    final current = await future;
    final next = switch (current) {
      TwmtThemeName.atelier => TwmtThemeName.forge,
      TwmtThemeName.forge => TwmtThemeName.atelier,
    };
    await setThemeName(next);
  }
}
