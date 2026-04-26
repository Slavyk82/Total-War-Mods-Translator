import 'package:twmt/i18n/strings.g.dart';

/// Display metadata for an [AppLocale]: native name and optional flag asset.
class AppLocaleInfo {
  final AppLocale locale;
  final String nativeName;
  final String? flagAsset;

  const AppLocaleInfo({
    required this.locale,
    required this.nativeName,
    this.flagAsset,
  });
}

/// Static mapping. Update this map when a new locale ships in `lib/i18n/`.
const Map<AppLocale, AppLocaleInfo> _localeInfo = {
  AppLocale.en: AppLocaleInfo(
    locale: AppLocale.en,
    nativeName: 'English',
    flagAsset: 'assets/flags/en.png',
  ),
  AppLocale.fr: AppLocaleInfo(
    locale: AppLocale.fr,
    nativeName: 'Français',
    flagAsset: 'assets/flags/fr.png',
  ),
  AppLocale.zh: AppLocaleInfo(
    locale: AppLocale.zh,
    nativeName: '简体中文',
    flagAsset: 'assets/flags/zh.png',
  ),
  AppLocale.ko: AppLocaleInfo(
    locale: AppLocale.ko,
    nativeName: '한국어',
    flagAsset: 'assets/flags/ko.png',
  ),
};

/// Returns the display info for [locale]. Throws if the map is missing
/// an entry — keeps the mapping honest as the locale set grows.
AppLocaleInfo infoFor(AppLocale locale) {
  final info = _localeInfo[locale];
  if (info == null) {
    throw StateError(
      'Missing AppLocaleInfo for $locale. Update _localeInfo in '
      'lib/i18n/app_locale_info.dart.',
    );
  }
  return info;
}

/// All locales for which display metadata is available, in declaration order.
/// Should match `AppLocale.values` in length once all locales are seeded.
List<AppLocale> get supportedLocales => _localeInfo.keys.toList(growable: false);
