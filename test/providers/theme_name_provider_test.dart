import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/providers/theme_name_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('ThemeNameNotifier', () {
    test('defaults to atelier on first run', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final name = await container.read(themeNameProvider.future);
      expect(name, TwmtThemeName.atelier);
    });

    test('setThemeName persists the choice', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeNameProvider.future);
      await container
          .read(themeNameProvider.notifier)
          .setThemeName(TwmtThemeName.forge);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('twmt_theme_name'), 'forge');
    });

    test('reads a previously persisted value', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'twmt_theme_name': 'forge'});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final name = await container.read(themeNameProvider.future);
      expect(name, TwmtThemeName.forge);
    });

    test('ignores unknown values and falls back to atelier', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'twmt_theme_name': 'neon_purple'});

      final container = ProviderContainer();
      addTearDown(container.dispose);

      final name = await container.read(themeNameProvider.future);
      expect(name, TwmtThemeName.atelier);
    });
  });
}
