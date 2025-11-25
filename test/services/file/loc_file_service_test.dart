import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/loc_file_service_impl.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

class MockTranslationUnitRepository extends Mock implements TranslationUnitRepository {}
class MockTranslationVersionRepository extends Mock implements TranslationVersionRepository {}
class MockProjectLanguageRepository extends Mock implements ProjectLanguageRepository {}

void main() {
  late LocFileServiceImpl service;
  late MockTranslationUnitRepository mockUnitRepository;
  late MockTranslationVersionRepository mockVersionRepository;
  late MockProjectLanguageRepository mockProjectLanguageRepository;

  setUp(() {
    mockUnitRepository = MockTranslationUnitRepository();
    mockVersionRepository = MockTranslationVersionRepository();
    mockProjectLanguageRepository = MockProjectLanguageRepository();

    service = LocFileServiceImpl(
      unitRepository: mockUnitRepository,
      versionRepository: mockVersionRepository,
      projectLanguageRepository: mockProjectLanguageRepository,
    );
  });

  group('LocFileServiceImpl', () {
    const projectId = 'project-1';
    const languageCode = 'en';
    const projectLanguageId = 'pl-1';

    final projectLanguage = ProjectLanguage(
      id: projectLanguageId,
      projectId: projectId,
      languageId: 'lang-en',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final unit1 = TranslationUnit(
      id: 'unit-1',
      projectId: projectId,
      key: 'ui_unit_name_001',
      sourceText: 'Spearmen',
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    final version1 = TranslationVersion(
      id: 'version-1',
      unitId: 'unit-1',
      projectLanguageId: projectLanguageId,
      translatedText: 'Lanciers',
      status: TranslationVersionStatus.approved,
      createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );

    group('generateLocFile', () {
      test('should generate .loc file with correct format', () async {
        // Arrange
        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(version1));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: true,
        );

        // Assert
        expect(result, isA<Ok<String, FileServiceException>>());
        final filePath = (result as Ok<String, FileServiceException>).value;
        expect(filePath, isNotEmpty);
        expect(filePath, endsWith('.loc'));
      });

      test('should escape quotes in translated text', () async {
        // Arrange
        final versionWithQuotes = version1.copyWith(
          translatedText: 'The "Elite" Spearmen',
        );

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(versionWithQuotes));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert - should not throw and should escape quotes
        expect(result, isA<Ok<String, FileServiceException>>());
      });

      test('should skip obsolete units', () async {
        // Arrange
        final obsoleteUnit = unit1.copyWith(isObsolete: true);

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([obsoleteUnit]));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert - should error because no units to export
        expect(result, isA<Err<String, FileServiceException>>());
        final error = (result as Err<String, FileServiceException>).error;
        expect(error.code, 'NO_TRANSLATIONS');
      });

      test('should filter by validation status when validatedOnly is true',
          () async {
        // Arrange
        final unvalidatedVersion = version1.copyWith(
          status: TranslationVersionStatus.translated,
        );

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(unvalidatedVersion));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: true,
        );

        // Assert - should error because no validated translations
        expect(result, isA<Err<String, FileServiceException>>());
      });

      test('should export all translations when validatedOnly is false',
          () async {
        // Arrange
        final translatedVersion = version1.copyWith(
          status: TranslationVersionStatus.translated,
        );

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(translatedVersion));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Ok<String, FileServiceException>>());
      });

      test('should return error when language not found', () async {
        // Arrange
        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([]));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Err<String, FileServiceException>>());
      });

      test('should return error when no translation units found', () async {
        // Arrange
        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([]));

        // Act
        final result = await service.generateLocFile(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Err<String, FileServiceException>>());
        final error = (result as Err<String, FileServiceException>).error;
        expect(error.code, 'NO_UNITS');
      });
    });

    group('generateLocFilesForLanguages', () {
      test('should generate .loc files for multiple languages', () async {
        // Arrange
        final frProjectLanguage = ProjectLanguage(
          id: 'pl-2',
          projectId: projectId,
          languageId: 'lang-fr',
          createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
          updatedAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        );

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage, frProjectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(version1));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: 'pl-2',
        )).thenAnswer((_) async => Ok(version1));

        // Act
        final result = await service.generateLocFilesForLanguages(
          projectId: projectId,
          languageCodes: ['en', 'fr'],
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Ok<Map<String, String>, FileServiceException>>());
        final files =
            (result as Ok<Map<String, String>, FileServiceException>).value;
        expect(files, hasLength(2));
        expect(files, contains('en'));
        expect(files, contains('fr'));
      });

      test('should return error if any language fails', () async {
        // Arrange
        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));

        // Act
        final result = await service.generateLocFilesForLanguages(
          projectId: projectId,
          languageCodes: ['en', 'nonexistent'],
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Err<Map<String, String>, FileServiceException>>());
      });
    });

    group('countExportableTranslations', () {
      test('should count validated translations when validatedOnly is true',
          () async {
        // Arrange
        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(version1));

        // Act
        final result = await service.countExportableTranslations(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: true,
        );

        // Assert
        expect(result, isA<Ok<int, FileServiceException>>());
        final count = (result as Ok<int, FileServiceException>).value;
        expect(count, 1);
      });

      test('should count all translations when validatedOnly is false',
          () async {
        // Arrange
        final translatedVersion = version1.copyWith(
          status: TranslationVersionStatus.translated,
        );

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([unit1]));
        when(() => mockVersionRepository.getByUnitAndProjectLanguage(
          unitId: 'unit-1',
          projectLanguageId: projectLanguageId,
        )).thenAnswer((_) async => Ok(translatedVersion));

        // Act
        final result = await service.countExportableTranslations(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Ok<int, FileServiceException>>());
        final count = (result as Ok<int, FileServiceException>).value;
        expect(count, 1);
      });

      test('should not count obsolete units', () async {
        // Arrange
        final obsoleteUnit = unit1.copyWith(isObsolete: true);

        when(() => mockProjectLanguageRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([projectLanguage]));
        when(() => mockUnitRepository.getByProject(projectId))
            .thenAnswer((_) async => Ok([obsoleteUnit]));

        // Act
        final result = await service.countExportableTranslations(
          projectId: projectId,
          languageCode: languageCode,
          validatedOnly: false,
        );

        // Assert
        expect(result, isA<Ok<int, FileServiceException>>());
        final count = (result as Ok<int, FileServiceException>).value;
        expect(count, 0);
      });
    });
  });
}
