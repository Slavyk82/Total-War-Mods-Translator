import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/i18n/strings.g.dart';

part 'app_locale_provider.g.dart';

/// Resolve a persisted locale string to a supported [AppLocale].
///
/// Matches on the full language tag first so region-qualified locales
/// round-trip exactly (e.g. 'pt-BR' -> [AppLocale.ptBr] instead of the
/// languageCode-only match that always resolved to [AppLocale.pt]).
/// Falls back to the bare language code so values persisted by older app
/// versions (which stored only the language code) keep resolving, then to
/// [AppLocale.en] for unknown values.
AppLocale resolveSavedAppLocale(String saved) {
  for (final locale in AppLocale.values) {
    if (locale.languageTag == saved) return locale;
  }
  for (final locale in AppLocale.values) {
    if (locale.languageCode == saved) return locale;
  }
  return AppLocale.en;
}

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
    return resolveSavedAppLocale(raw);
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
    // Persist the full language tag (e.g. 'pt-BR'), not the bare language
    // code: AppLocale.pt and AppLocale.ptBr share languageCode 'pt', so the
    // code alone cannot round-trip region-qualified locales.
    await prefs.setString(_prefsKey, locale.languageTag);
  }
}
