import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/providers/project_detail_providers.dart';
import 'package:twmt/providers/shared/repository_providers.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';

import '../helpers/mock_providers.dart';

class MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class MockLanguageRepository extends Mock implements LanguageRepository {}

/// Builds a [ProjectLanguage] row. The provider only reads `languageId`, so the
/// other fields are filler but must be valid.
ProjectLanguage _projectLanguage({
  required String id,
  required String projectId,
  required String languageId,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return ProjectLanguage(
    id: id,
    projectId: projectId,
    languageId: languageId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  const projectId = 'proj-1';

  setUpAll(() => registerFallbackValue(<String>[]));

  late MockProjectLanguageRepository mockProjectLangRepo;
  late MockLanguageRepository mockLangRepo;
  late ProviderContainer container;

  ProviderContainer buildContainer() => ProviderContainer(overrides: [
        projectLanguageRepositoryProvider.overrideWithValue(mockProjectLangRepo),
        languageRepositoryProvider.overrideWithValue(mockLangRepo),
      ]);

  setUp(() {
    mockProjectLangRepo = MockProjectLanguageRepository();
    mockLangRepo = MockLanguageRepository();
    container = buildContainer();
  });

  tearDown(() => container.dispose());

  group('projectLanguagesProvider', () {
    test('maps each project language to its enriched Language record', () async {
      final pl1 = _projectLanguage(id: 'pl-1', projectId: projectId, languageId: 'fr');
      final pl2 = _projectLanguage(id: 'pl-2', projectId: projectId, languageId: 'de');
      final frLang = createMockLanguage(id: 'fr', name: 'French', code: 'fr');
      final deLang = createMockLanguage(id: 'de', name: 'German', code: 'de');

      when(() => mockProjectLangRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([pl1, pl2]));
      when(() => mockLangRepo.getByIds(['fr', 'de'])).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([frLang, deLang]));

      final details = await container.read(projectLanguagesProvider(projectId).future);

      expect(details, hasLength(2));
      expect(details[0].projectLanguage, pl1);
      expect(details[0].language, frLang);
      expect(details[1].projectLanguage, pl2);
      expect(details[1].language, deLang);

      // Defaults: no counts wired in by the provider yet.
      expect(details[0].totalUnits, 0);
      expect(details[0].translatedUnits, 0);

      verify(() => mockProjectLangRepo.getByProject(projectId)).called(1);
      verify(() => mockLangRepo.getByIds(['fr', 'de'])).called(1);
    });

    test('skips project languages whose Language record is missing from getByIds',
        () async {
      final pl1 = _projectLanguage(id: 'pl-1', projectId: projectId, languageId: 'fr');
      final pl2 = _projectLanguage(id: 'pl-2', projectId: projectId, languageId: 'de');
      // getByIds returns only the French language; German is absent.
      final frLang = createMockLanguage(id: 'fr', name: 'French', code: 'fr');

      when(() => mockProjectLangRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([pl1, pl2]));
      when(() => mockLangRepo.getByIds(['fr', 'de'])).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([frLang]));

      final details = await container.read(projectLanguagesProvider(projectId).future);

      expect(details, hasLength(1));
      expect(details.single.language, frLang);
      expect(details.single.projectLanguage, pl1);
    });

    test('returns an empty list when the project has no languages', () async {
      when(() => mockProjectLangRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([]));
      // languageIds is empty -> getByIds([]) returns [].
      when(() => mockLangRepo.getByIds(<String>[])).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([]));

      final details = await container.read(projectLanguagesProvider(projectId).future);

      expect(details, isEmpty);
      verify(() => mockLangRepo.getByIds(<String>[])).called(1);
    });

    test('throws when getByProject returns Err', () async {
      when(() => mockProjectLangRepo.getByProject(projectId)).thenAnswer((_) async =>
          Err<List<ProjectLanguage>, TWMTDatabaseException>(
              TWMTDatabaseException('boom')));

      // Keep the provider alive so it is not disposed mid-load before the
      // error surfaces (a bare read(...future) is a transient subscription).
      container.listen(projectLanguagesProvider(projectId), (_, _) {});
      await pumpEventQueue();

      final state = container.read(projectLanguagesProvider(projectId));
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());

      // getByIds must never be reached once the first fetch fails.
      verifyNever(() => mockLangRepo.getByIds(any()));
    });

    test('throws when getByIds returns Err', () async {
      final pl1 = _projectLanguage(id: 'pl-1', projectId: projectId, languageId: 'fr');

      when(() => mockProjectLangRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([pl1]));
      when(() => mockLangRepo.getByIds(['fr'])).thenAnswer((_) async =>
          Err<List<Language>, TWMTDatabaseException>(
              TWMTDatabaseException('lang boom')));

      container.listen(projectLanguagesProvider(projectId), (_, _) {});
      await pumpEventQueue();

      final state = container.read(projectLanguagesProvider(projectId));
      expect(state.hasError, isTrue);
      expect(state.error, isA<Exception>());
    });

    test('is parameterized by project id (distinct args fetch distinct data)',
        () async {
      const otherProjectId = 'proj-2';
      final plA = _projectLanguage(id: 'pl-a', projectId: projectId, languageId: 'fr');
      final plB =
          _projectLanguage(id: 'pl-b', projectId: otherProjectId, languageId: 'de');
      final frLang = createMockLanguage(id: 'fr', name: 'French', code: 'fr');
      final deLang = createMockLanguage(id: 'de', name: 'German', code: 'de');

      when(() => mockProjectLangRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([plA]));
      when(() => mockProjectLangRepo.getByProject(otherProjectId)).thenAnswer(
          (_) async => Ok<List<ProjectLanguage>, TWMTDatabaseException>([plB]));
      when(() => mockLangRepo.getByIds(['fr'])).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([frLang]));
      when(() => mockLangRepo.getByIds(['de'])).thenAnswer(
          (_) async => Ok<List<Language>, TWMTDatabaseException>([deLang]));

      final a = await container.read(projectLanguagesProvider(projectId).future);
      final b = await container.read(projectLanguagesProvider(otherProjectId).future);

      expect(a.single.language, frLang);
      expect(b.single.language, deLang);
    });
  });

  group('ProjectLanguageDetails.progressPercent', () {
    final pl = _projectLanguage(id: 'pl', projectId: projectId, languageId: 'fr');
    final lang = createMockLanguage(id: 'fr');

    test('returns 0 when there are no units (division-by-zero guard)', () {
      final details = ProjectLanguageDetails(projectLanguage: pl, language: lang);
      expect(details.totalUnits, 0);
      expect(details.progressPercent, 0.0);
    });

    test('computes translated / total as a percentage', () {
      final details = ProjectLanguageDetails(
        projectLanguage: pl,
        language: lang,
        totalUnits: 200,
        translatedUnits: 50,
      );
      expect(details.progressPercent, 25.0);
    });

    test('reaches 100 when every unit is translated', () {
      final details = ProjectLanguageDetails(
        projectLanguage: pl,
        language: lang,
        totalUnits: 10,
        translatedUnits: 10,
      );
      expect(details.progressPercent, 100.0);
    });
  });

  group('re-exported repository providers', () {
    test('translationUnitRepositoryProvider symbol is re-exported', () {
      // Smoke check that the backward-compat re-export resolves; reading the
      // provider object (not its value) needs no ServiceLocator.
      expect(translationUnitRepositoryProvider, isNotNull);
      expect(translationVersionRepositoryProvider, isNotNull);
    });
  });
}
