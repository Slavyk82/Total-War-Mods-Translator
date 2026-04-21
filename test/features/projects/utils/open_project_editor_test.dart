import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/features/projects/providers/project_detail_providers.dart';
import 'package:twmt/features/projects/utils/open_project_editor.dart';
import 'package:twmt/features/settings/providers/settings_providers.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/services/settings/settings_service.dart';

import '../../../helpers/test_helpers.dart';

class _FakeSettingsService implements SettingsService {
  _FakeSettingsService(this._defaultCode);
  final String _defaultCode;

  @override
  Future<String> getString(String key, {String defaultValue = ''}) async {
    if (key == SettingsKeys.defaultTargetLanguage) return _defaultCode;
    return defaultValue;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProjectLanguageDetails _pld(String id, String code, String name) {
  return ProjectLanguageDetails(
    projectLanguage: ProjectLanguage(
      id: 'pl_$id',
      projectId: 'p',
      languageId: id,
      progressPercent: 0.0,
      createdAt: 1,
      updatedAt: 1,
    ),
    language: Language(
      id: id,
      code: code,
      name: name,
      nativeName: name,
    ),
  );
}

void main() {
  setUp(setupMockServices);
  tearDown(tearDownMockServices);

  testWidgets('resolves to settings default when present in project',
      (tester) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(_FakeSettingsService('de')),
      projectLanguagesProvider('p').overrideWith((ref) async => [
            _pld('fr-id', 'fr', 'French'),
            _pld('de-id', 'de', 'German'),
          ]),
    ]);
    addTearDown(container.dispose);

    final id = await resolveTargetLanguageId(container.read, 'p');
    expect(id, 'de-id');
  });

  testWidgets('falls back to first language when default missing',
      (tester) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(_FakeSettingsService('es')),
      projectLanguagesProvider('p').overrideWith((ref) async => [
            _pld('fr-id', 'fr', 'French'),
            _pld('de-id', 'de', 'German'),
          ]),
    ]);
    addTearDown(container.dispose);

    final id = await resolveTargetLanguageId(container.read, 'p');
    expect(id, 'fr-id');
  });

  testWidgets('returns null when project has no languages', (tester) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(_FakeSettingsService('fr')),
      projectLanguagesProvider('p').overrideWith((ref) async => []),
    ]);
    addTearDown(container.dispose);

    final id = await resolveTargetLanguageId(container.read, 'p');
    expect(id, isNull);
  });
}
