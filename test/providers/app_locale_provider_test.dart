import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/i18n/strings.g.dart';
import 'package:twmt/providers/app_locale_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to en when no preference is persisted', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final locale = await container.read(appLocaleProvider.future);

    expect(locale, AppLocale.en);
  });

  test('reads persisted locale on first build', () async {
    SharedPreferences.setMockInitialValues({'twmt_app_locale': 'fr'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final locale = await container.read(appLocaleProvider.future);

    expect(locale, AppLocale.fr);
  });

  test('setLocale persists the new value and updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appLocaleProvider.future);
    await container
        .read(appLocaleProvider.notifier)
        .setLocale(AppLocale.fr);

    final locale = await container.read(appLocaleProvider.future);
    expect(locale, AppLocale.fr);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('twmt_app_locale'), 'fr');
  });

  test('setLocale(null) clears the preference (system default)', () async {
    SharedPreferences.setMockInitialValues({'twmt_app_locale': 'fr'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(appLocaleProvider.future);
    await container
        .read(appLocaleProvider.notifier)
        .setLocale(null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('twmt_app_locale'), isNull);
  });

  test('unknown persisted code falls back to en', () async {
    SharedPreferences.setMockInitialValues({'twmt_app_locale': 'klingon'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final locale = await container.read(appLocaleProvider.future);
    expect(locale, AppLocale.en);
  });
}
