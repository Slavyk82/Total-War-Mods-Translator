import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/config/settings_keys.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/services/settings/settings_service.dart';
import 'package:twmt/providers/language_settings_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/providers/shared/service_providers.dart';

class MockSettingsService extends Mock implements SettingsService {}

class MockLanguageRepository extends Mock implements LanguageRepository {}

class MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class MockGlossaryRepository extends Mock implements GlossaryRepository {}

Language _lang({
  required String id,
  required String code,
  required String name,
  bool isCustom = false,
}) {
  return Language(
    id: id,
    code: code,
    name: name,
    nativeName: name,
    isActive: true,
    isCustom: isCustom,
  );
}

void main() {
  // `addCustomLanguage` / `insert(...)` matches over a Language model, so a
  // fallback is needed for the `any()` used in those stubs.
  setUpAll(() {
    registerFallbackValue(
      _lang(id: 'fallback', code: 'xx', name: 'Fallback', isCustom: true),
    );
  });

  late MockSettingsService mockSettings;
  late MockLanguageRepository mockLangRepo;
  late MockProjectLanguageRepository mockProjLangRepo;
  late MockGlossaryRepository mockGlossaryRepo;
  late ProviderContainer container;

  /// Permissive stubs so the notifier `build()` (and the most common mutator
  /// paths) complete without `MissingStubError`.
  void stubDefaults() {
    when(() => mockSettings.getString(any(),
            defaultValue: any(named: 'defaultValue')))
        .thenAnswer((_) async => SettingsKeys.defaultTargetLanguageValue);
    when(() => mockSettings.setString(any(), any()))
        .thenAnswer((_) async => const Ok<void, TWMTDatabaseException>(null));

    when(() => mockLangRepo.getAll())
        .thenAnswer((_) async => const Ok<List<Language>, TWMTDatabaseException>(
              <Language>[],
            ));
  }

  ProviderContainer buildContainer() {
    return ProviderContainer(overrides: [
      // Leaf bridge providers — overriding these keeps ServiceLocator out.
      settingsServiceProvider.overrideWithValue(mockSettings),
      languageRepositoryProvider.overrideWithValue(mockLangRepo),
      projectLanguageRepositoryProvider.overrideWithValue(mockProjLangRepo),
      glossaryRepositoryProvider.overrideWithValue(mockGlossaryRepo),
    ]);
  }

  setUp(() {
    mockSettings = MockSettingsService();
    mockLangRepo = MockLanguageRepository();
    mockProjLangRepo = MockProjectLanguageRepository();
    mockGlossaryRepo = MockGlossaryRepository();
    stubDefaults();
    container = buildContainer();
  });

  tearDown(() => container.dispose());

  group('settingsLanguageRepository provider', () {
    test('exposes the overridden language repository', () {
      expect(
        container.read(settingsLanguageRepositoryProvider),
        same(mockLangRepo),
      );
    });
  });

  group('LanguageSettings.build()', () {
    test('maps repository languages and the default code from settings',
        () async {
      final langs = [
        _lang(id: '1', code: 'de', name: 'German'),
        _lang(id: '2', code: 'fr', name: 'French', isCustom: true),
      ];
      when(() => mockLangRepo.getAll()).thenAnswer(
        (_) async => Ok<List<Language>, TWMTDatabaseException>(langs),
      );
      when(() => mockSettings.getString(SettingsKeys.defaultTargetLanguage,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'de');

      final state = await container.read(languageSettingsProvider.future);

      expect(state.languages, langs);
      expect(state.defaultLanguageCode, 'de');
      expect(state.isLoading, isFalse);
      expect(state.error, isNull);
      verify(() => mockLangRepo.getAll()).called(1);
    });

    test('falls back to an empty language list when the repo returns Err',
        () async {
      when(() => mockLangRepo.getAll()).thenAnswer(
        (_) async => Err<List<Language>, TWMTDatabaseException>(
          TWMTDatabaseException('boom'),
        ),
      );

      final state = await container.read(languageSettingsProvider.future);

      expect(state.languages, isEmpty);
      // Default code still resolved from settings (stubbed default value).
      expect(state.defaultLanguageCode, SettingsKeys.defaultTargetLanguageValue);
    });
  });

  group('LanguageSettings.setDefaultLanguage', () {
    test('persists the language code and reports success', () async {
      await container.read(languageSettingsProvider.future);

      final result = await container
          .read(languageSettingsProvider.notifier)
          .setDefaultLanguage('es');

      expect(result, (true, null));
      verify(() =>
              mockSettings.setString(SettingsKeys.defaultTargetLanguage, 'es'))
          .called(1);
    });

    test('updates state with the new default language code', () async {
      await container.read(languageSettingsProvider.future);

      await container
          .read(languageSettingsProvider.notifier)
          .setDefaultLanguage('it');

      final state = await container.read(languageSettingsProvider.future);
      expect(state.defaultLanguageCode, 'it');
    });

    test('returns failure tuple when persistence throws', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockSettings.setString(
          SettingsKeys.defaultTargetLanguage, 'zz')).thenThrow(
        Exception('disk full'),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .setDefaultLanguage('zz');

      expect(result.$1, isFalse);
      expect(result.$2, contains('Failed to set default language'));
    });
  });

  group('LanguageSettings.addCustomLanguage', () {
    test('rejects an empty code', () async {
      await container.read(languageSettingsProvider.future);

      final result = await container
          .read(languageSettingsProvider.notifier)
          .addCustomLanguage(code: '   ', name: 'Klingon');

      expect(result, (false, 'Language code is required'));
      verifyNever(() => mockLangRepo.insert(any()));
    });

    test('rejects an empty name', () async {
      await container.read(languageSettingsProvider.future);

      final result = await container
          .read(languageSettingsProvider.notifier)
          .addCustomLanguage(code: 'kl', name: '  ');

      expect(result, (false, 'Language name is required'));
      verifyNever(() => mockLangRepo.insert(any()));
    });

    test('rejects a code that already exists', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.codeExists('kl')).thenAnswer(
        (_) async => const Ok<bool, TWMTDatabaseException>(true),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .addCustomLanguage(code: 'KL', name: 'Klingon');

      expect(result.$1, isFalse);
      expect(result.$2, contains('already exists'));
      verify(() => mockLangRepo.codeExists('kl')).called(1);
      verifyNever(() => mockLangRepo.insert(any()));
    });

    test('inserts a normalized custom language on success', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.codeExists('kl')).thenAnswer(
        (_) async => const Ok<bool, TWMTDatabaseException>(false),
      );
      when(() => mockLangRepo.insert(any())).thenAnswer(
        (invocation) async => Ok<Language, TWMTDatabaseException>(
          invocation.positionalArguments.first as Language,
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .addCustomLanguage(code: '  KL  ', name: '  Klingon  ');

      expect(result, (true, null));
      final captured =
          verify(() => mockLangRepo.insert(captureAny())).captured.single
              as Language;
      // code lowercased + trimmed, name trimmed, marked custom + active.
      expect(captured.code, 'kl');
      expect(captured.name, 'Klingon');
      expect(captured.nativeName, 'Klingon');
      expect(captured.isCustom, isTrue);
      expect(captured.isActive, isTrue);
    });

    test('returns the repository error message when insert fails', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.codeExists('kl')).thenAnswer(
        (_) async => const Ok<bool, TWMTDatabaseException>(false),
      );
      when(() => mockLangRepo.insert(any())).thenAnswer(
        (_) async => Err<Language, TWMTDatabaseException>(
          TWMTDatabaseException('insert failed'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .addCustomLanguage(code: 'kl', name: 'Klingon');

      expect(result, (false, 'insert failed'));
    });
  });

  group('LanguageSettings.deleteLanguage', () {
    test('returns "not found" when getById errors', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('missing')).thenAnswer(
        (_) async => Err<Language, TWMTDatabaseException>(
          TWMTDatabaseException('nope'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('missing');

      expect(result, (false, 'Language not found'));
    });

    test('refuses to delete a system (non-custom) language', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('sys')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'sys', code: 'en', name: 'English'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('sys');

      expect(result, (false, 'System languages cannot be deleted'));
    });

    test('refuses to delete the currently default language', () async {
      // Default code resolves to 'fr' (stubbed); the custom language uses 'fr'.
      when(() => mockSettings.getString(SettingsKeys.defaultTargetLanguage,
          defaultValue: any(named: 'defaultValue'))).thenAnswer((_) async => 'fr');
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'fr', name: 'French', isCustom: true),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result.$1, isFalse);
      expect(result.$2, contains('Cannot delete the default language'));
    });

    test('blocks deletion when the language is used by projects', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(2),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result.$1, isFalse);
      expect(result.$2, contains('used in one or more projects'));
      verifyNever(() => mockGlossaryRepo.countByTargetLanguageId(any()));
    });

    test('surfaces an error when the project-usage check fails', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => Err<int, TWMTDatabaseException>(
          TWMTDatabaseException('count failed'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result.$1, isFalse);
      expect(result.$2, contains('Failed to check language usage'));
    });

    test('blocks deletion when the language is a glossary target', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockGlossaryRepo.countByTargetLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(1),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result.$1, isFalse);
      expect(result.$2, contains('target of one or more glossaries'));
      verifyNever(() => mockLangRepo.deleteWithTranslationMemoryCleanup(any()));
    });

    test('surfaces an error when the glossary-usage check fails', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockGlossaryRepo.countByTargetLanguageId('c1')).thenAnswer(
        (_) async => Err<int, TWMTDatabaseException>(
          TWMTDatabaseException('glossary count failed'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result.$1, isFalse);
      expect(result.$2, contains('Failed to check glossary usage'));
    });

    test('deletes a custom language with TM cleanup on the happy path',
        () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockGlossaryRepo.countByTargetLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockLangRepo.deleteWithTranslationMemoryCleanup('c1'))
          .thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(3),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result, (true, null));
      verify(() => mockLangRepo.deleteWithTranslationMemoryCleanup('c1'))
          .called(1);
    });

    test('maps a foreign-key delete error to the project-usage message',
        () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockGlossaryRepo.countByTargetLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockLangRepo.deleteWithTranslationMemoryCleanup('c1'))
          .thenAnswer(
        (_) async => Err<int, TWMTDatabaseException>(
          TWMTDatabaseException('FOREIGN KEY constraint failed'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result.$1, isFalse);
      expect(result.$2, contains('used in one or more projects'));
    });

    test('returns the raw delete error message for non-FK failures', () async {
      await container.read(languageSettingsProvider.future);
      when(() => mockLangRepo.getById('c1')).thenAnswer(
        (_) async => Ok<Language, TWMTDatabaseException>(
          _lang(id: 'c1', code: 'kl', name: 'Klingon', isCustom: true),
        ),
      );
      when(() => mockProjLangRepo.countByLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockGlossaryRepo.countByTargetLanguageId('c1')).thenAnswer(
        (_) async => const Ok<int, TWMTDatabaseException>(0),
      );
      when(() => mockLangRepo.deleteWithTranslationMemoryCleanup('c1'))
          .thenAnswer(
        (_) async => Err<int, TWMTDatabaseException>(
          TWMTDatabaseException('some other db error'),
        ),
      );

      final result = await container
          .read(languageSettingsProvider.notifier)
          .deleteLanguage('c1');

      expect(result, (false, 'some other db error'));
    });
  });
}
