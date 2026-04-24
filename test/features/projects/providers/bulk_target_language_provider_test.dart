import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twmt/features/projects/providers/bulk_target_language_provider.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to null when no pref stored', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(bulkTargetLanguageProvider.future), isNull);
  });

  test('setLanguage persists and updates state', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkTargetLanguageProvider.future);
    await container.read(bulkTargetLanguageProvider.notifier).setLanguage('fr');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('projects_bulk_target_lang'), 'fr');
    expect(container.read(bulkTargetLanguageProvider).value, 'fr');
  });

  test('loads existing pref on init', () async {
    SharedPreferences.setMockInitialValues({'projects_bulk_target_lang': 'de'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(await container.read(bulkTargetLanguageProvider.future), 'de');
  });

  test('setLanguage(null) clears pref', () async {
    SharedPreferences.setMockInitialValues({'projects_bulk_target_lang': 'de'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(bulkTargetLanguageProvider.future);
    await container.read(bulkTargetLanguageProvider.notifier).setLanguage(null);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('projects_bulk_target_lang'), isNull);
    expect(container.read(bulkTargetLanguageProvider).value, isNull);
  });
}
