import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'theme_name_provider.g.dart';

/// Identifies which TWMT palette/typography couple is active.
///
/// Dark themes (atelier, forge, slate, warpstone, shogun) share a dark
/// builder; [vellum] is the only light theme and is wired through a
/// separate [Brightness.light] code path in [AppTheme].
enum TwmtThemeName {
  atelier,
  forge,
  slate,
  vellum,
  warpstone,
  shogun;

  static TwmtThemeName? fromString(String? value) {
    switch (value) {
      case 'atelier':
        return TwmtThemeName.atelier;
      case 'forge':
        return TwmtThemeName.forge;
      case 'slate':
        return TwmtThemeName.slate;
      case 'vellum':
        return TwmtThemeName.vellum;
      case 'warpstone':
        return TwmtThemeName.warpstone;
      case 'shogun':
        return TwmtThemeName.shogun;
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

  /// Cycle forward through the available palettes in declaration order,
  /// wrapping back to the first value after the last one.
  Future<void> cycleTheme() async {
    final current = await future;
    const values = TwmtThemeName.values;
    final next = values[(current.index + 1) % values.length];
    await setThemeName(next);
  }
}
