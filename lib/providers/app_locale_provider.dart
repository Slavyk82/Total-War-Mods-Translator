import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/i18n/strings.g.dart';

part 'app_locale_provider.g.dart';

/// Persisted Riverpod notifier carrying the user's app-UI locale.
///
/// Storage key: `twmt_app_locale`. Default: [AppLocale.en].
/// Calling [setLocale] with `null` clears the preference (the persisted
/// entry is removed, so subsequent rebuilds rebase on the device locale
/// or the default).
@riverpod
class AppLocaleNotifier extends _$AppLocaleNotifier {
  static const String _prefsKey = 'twmt_app_locale';

  @override
  Future<AppLocale> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return AppLocale.en;
    return AppLocale.values.firstWhere(
      (l) => l.languageCode == raw,
      orElse: () => AppLocale.en,
    );
  }

  /// Switch the active locale. Pass `null` to clear the preference.
  Future<void> setLocale(AppLocale? locale) async {
    final prefs = await SharedPreferences.getInstance();
    if (locale == null) {
      await prefs.remove(_prefsKey);
      ref.invalidateSelf();
      return;
    }

    state = AsyncValue.data(locale);
    await prefs.setString(_prefsKey, locale.languageCode);
  }
}
