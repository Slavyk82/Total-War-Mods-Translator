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

  // Regression tests for the pt-BR round-trip. AppLocale.pt and
  // AppLocale.ptBr share languageCode 'pt' and pt precedes ptBr in
  // AppLocale.values, so the old languageCode-only persistence + matching
  // could never restore ptBr: a user who picked 'Português (Brasil)'
  // silently got European Portuguese on every launch. The fix persists the
  // full languageTag ('pt-BR') and resolves saved values tag-first, with a
  // bare-language-code fallback for values written by older app versions.
  group('resolveSavedAppLocale', () {
    // (saved string, expected locale)
    const cases = <(String, AppLocale)>[
      // Full language tags round-trip exactly — the regression case.
      ('pt-BR', AppLocale.ptBr),
      ('pt', AppLocale.pt),
      ('en', AppLocale.en),
      ('fr', AppLocale.fr),
      // Legacy bare language codes persisted by older app versions.
      ('de', AppLocale.de),
      ('zh', AppLocale.zh),
      ('ru', AppLocale.ru),
      // Unknown values fall back to English. 'pt-PT' is not a supported
      // tag and is never produced by the (tag-persisting) save path, so it
      // takes the unknown-value fallback rather than a base-code guess.
      ('xx', AppLocale.en),
      ('', AppLocale.en),
      ('pt-PT', AppLocale.en),
    ];

    for (final (saved, expected) in cases) {
      test("'$saved' resolves to $expected", () {
        expect(resolveSavedAppLocale(saved), expected);
      });
    }
  });

  group('pt-BR persistence round-trip', () {
    test('restores a persisted pt-BR locale as AppLocale.ptBr (not pt)',
        () async {
      SharedPreferences.setMockInitialValues({'twmt_app_locale': 'pt-BR'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final locale = await container.read(appLocaleProvider.future);
      expect(locale, AppLocale.ptBr,
          reason: "a saved 'pt-BR' must restore Brazilian Portuguese, not "
              'silently fall back to European Portuguese');
    });

    test('setLocale(ptBr) persists the full languageTag pt-BR', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(appLocaleProvider.future);
      await container
          .read(appLocaleProvider.notifier)
          .setLocale(AppLocale.ptBr);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('twmt_app_locale'), 'pt-BR',
          reason: "persisting the bare languageCode ('pt') loses the region "
              'and can never round-trip back to ptBr');
    });

    test('setLocale(ptBr) then app restart restores ptBr', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(appLocaleProvider.future);
      await container
          .read(appLocaleProvider.notifier)
          .setLocale(AppLocale.ptBr);

      // Simulate the next app launch: a fresh container reading the same
      // (mocked) preferences store.
      final restartContainer = ProviderContainer();
      addTearDown(restartContainer.dispose);
      expect(
        await restartContainer.read(appLocaleProvider.future),
        AppLocale.ptBr,
      );
    });
  });
}
