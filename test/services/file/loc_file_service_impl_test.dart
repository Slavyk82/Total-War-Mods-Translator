import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/config/app_constants.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/language.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/repositories/language_repository.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/loc_file_service_impl.dart';

import '../../helpers/noop_logger.dart';

class MockUnitRepository extends Mock implements TranslationUnitRepository {}

class MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

class MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

class MockLanguageRepository extends Mock implements LanguageRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  const projectId = 'project-1';
  const languageCode = 'fr';
  const languageId = 'lang_fr';
  const projectLanguageId = 'pl-1';

  late MockUnitRepository unitRepo;
  late MockVersionRepository versionRepo;
  late MockProjectLanguageRepository projectLanguageRepo;
  late MockLanguageRepository languageRepo;
  late LocFileServiceImpl service;
  late Directory tempDir;

  Language buildLanguage() => const Language(
        id: languageId,
        code: languageCode,
        name: 'French',
        nativeName: 'Français',
      );

  ProjectLanguage buildProjectLanguage({String langId = languageId}) =>
      ProjectLanguage(
        id: projectLanguageId,
        projectId: projectId,
        languageId: langId,
        createdAt: 1,
        updatedAt: 1,
      );

  TranslationUnit buildUnit({
    required String id,
    required String key,
    required String sourceText,
    String? sourceLocFile,
  }) =>
      TranslationUnit(
        id: id,
        projectId: projectId,
        key: key,
        sourceText: sourceText,
        sourceLocFile: sourceLocFile,
        createdAt: 1,
        updatedAt: 1,
      );

  TranslationVersion buildVersion({
    required String unitId,
    String? translatedText,
    TranslationVersionStatus status = TranslationVersionStatus.translated,
  }) =>
      TranslationVersion(
        id: 'ver-$unitId',
        unitId: unitId,
        projectLanguageId: projectLanguageId,
        translatedText: translatedText,
        status: status,
        createdAt: 1,
        updatedAt: 1,
      );

  setUp(() async {
    unitRepo = MockUnitRepository();
    versionRepo = MockVersionRepository();
    projectLanguageRepo = MockProjectLanguageRepository();
    languageRepo = MockLanguageRepository();

    tempDir = await Directory.systemTemp.createTemp('loc_file_service_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, (call) async {
      return tempDir.path;
    });

    service = LocFileServiceImpl(
      unitRepository: unitRepo,
      versionRepository: versionRepo,
      projectLanguageRepository: projectLanguageRepo,
      languageRepository: languageRepo,
      logger: NoopLogger(),
    );

    // Sensible default stubs; individual tests override as needed.
    when(() => languageRepo.getByCode(languageCode))
        .thenAnswer((_) async => Ok(buildLanguage()));
    when(() => projectLanguageRepo.getByProject(projectId))
        .thenAnswer((_) async => Ok([buildProjectLanguage()]));
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Stub version lookup to return Err (no version) for every unit.
  void stubNoVersions() {
    when(() => versionRepo.getByUnitAndProjectLanguage(
          unitId: any(named: 'unitId'),
          projectLanguageId: any(named: 'projectLanguageId'),
        )).thenAnswer(
        (_) async => Err(TWMTDatabaseException('no version')));
  }

  group('buildLocInternalPath', () {
    test('builds prefixed lowercase path preserving directory', () {
      final result = LocFileServiceImpl.buildLocInternalPath(
        'text/db/Something.loc',
        'fr',
      );
      expect(result, 'text/db/!!!!!!!!!!_fr_twmt_something.loc');
    });

    test('handles file with no directory', () {
      final result = LocFileServiceImpl.buildLocInternalPath(
        'Something.loc',
        'de',
      );
      expect(result, '!!!!!!!!!!_de_twmt_something.loc');
    });

    test('honours custom prefix and backslash directories', () {
      final result = LocFileServiceImpl.buildLocInternalPath(
        'text\\db\\Names.loc',
        'es',
        prefix: 'zzz',
      );
      expect(result, 'text/db/zzz_es_twmt_names.loc');
    });

    test('handles path without .loc extension', () {
      final result = LocFileServiceImpl.buildLocInternalPath(
        'text/db/plain',
        'it',
      );
      expect(result, 'text/db/!!!!!!!!!!_it_twmt_plain.loc');
    });
  });

  group('countExportableTranslations', () {
    test('counts units, using source fallback when no version', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(id: 'u1', key: 'K1', sourceText: 'A'),
            buildUnit(id: 'u2', key: 'K2', sourceText: 'B'),
          ]));
      stubNoVersions();

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isOk, isTrue);
      expect(result.unwrap(), 2);
    });

    test('validatedOnly counts only translated versions', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(id: 'u1', key: 'K1', sourceText: 'A'),
            buildUnit(id: 'u2', key: 'K2', sourceText: 'B'),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u1',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u1',
            translatedText: 'Aa',
          )));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u2',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u2',
            translatedText: 'Bb',
            status: TranslationVersionStatus.pending,
          )));

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: true,
      );

      expect(result.unwrap(), 1);
    });

    test('counts all units when not validatedOnly with versions', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(id: 'u1', key: 'K1', sourceText: 'A'),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u1',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u1',
            translatedText: 'Aa',
          )));

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.unwrap(), 1);
    });

    test('returns Err when project languages load fails', () async {
      when(() => projectLanguageRepo.getByProject(projectId)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('boom')));

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('project languages'));
    });

    test('returns Err when language code not found', () async {
      when(() => languageRepo.getByCode(languageCode)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('missing')));

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('not found in system'));
    });

    test('returns Err when language not in project', () async {
      when(() => projectLanguageRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok([buildProjectLanguage(langId: 'lang_other')]));

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('not found in project'));
    });

    test('returns Err when units load fails', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('db down')));

      final result = await service.countExportableTranslations(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('translation units'));
    });
  });

  group('generateLocFilesGroupedBySource', () {
    test('generates one TSV per source file with correct content',
        () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'K1',
              sourceText: 'Hello',
              sourceLocFile: 'text/db/a.loc',
            ),
            buildUnit(
              id: 'u2',
              key: 'K2',
              sourceText: 'World',
              sourceLocFile: 'text/db/b.loc',
            ),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u1',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u1',
            translatedText: 'Bonjour',
          )));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u2',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u2',
            translatedText: 'Monde',
          )));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isOk, isTrue);
      final files = result.unwrap();
      expect(files.length, 2);

      final pathA = files.firstWhere(
          (f) => f.internalPath.contains('twmt_a.loc'));
      final content = await File(pathA.tsvPath).readAsString();
      expect(content, startsWith('key\ttext\ttooltip\n'));
      expect(content, contains('#Loc;1;text/db/!!!!!!!!!!_fr_twmt_a.loc'));
      expect(content, contains('K1\tBonjour\tfalse'));
      expect(pathA.internalPath, 'text/db/!!!!!!!!!!_fr_twmt_a.loc');
      expect(await File(pathA.tsvPath).exists(), isTrue);
    });

    test('falls back to default source file when unit has none', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(id: 'u1', key: 'K1', sourceText: 'Hi'),
          ]));
      stubNoVersions();

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      final files = result.unwrap();
      expect(files.length, 1);
      expect(files.first.internalPath,
          'text/db/!!!!!!!!!!_fr_twmt_translations.loc');
      final content = await File(files.first.tsvPath).readAsString();
      // No version => source text used as fallback.
      expect(content, contains('K1\tHi\tfalse'));
    });

    test('excludeKeys drops matching units', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'KEEP',
              sourceText: 'A',
              sourceLocFile: 'text/db/a.loc',
            ),
            buildUnit(
              id: 'u2',
              key: 'DROP',
              sourceText: 'B',
              sourceLocFile: 'text/db/a.loc',
            ),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: any(named: 'unitId'),
            projectLanguageId: any(named: 'projectLanguageId'),
          )).thenAnswer(
          (_) async => Err(TWMTDatabaseException('no version')));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
        excludeKeys: {'DROP'},
      );

      final files = result.unwrap();
      expect(files.length, 1);
      final content = await File(files.first.tsvPath).readAsString();
      expect(content, contains('KEEP\t'));
      expect(content, isNot(contains('DROP\t')));
    });

    test('validatedOnly skips non-translated versions', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'K1',
              sourceText: 'A',
              sourceLocFile: 'text/db/a.loc',
            ),
            buildUnit(
              id: 'u2',
              key: 'K2',
              sourceText: 'B',
              sourceLocFile: 'text/db/a.loc',
            ),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u1',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u1',
            translatedText: 'Aa',
          )));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u2',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u2',
            translatedText: 'Bb',
            status: TranslationVersionStatus.needsReview,
          )));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: true,
      );

      final content =
          await File(result.unwrap().first.tsvPath).readAsString();
      expect(content, contains('K1\tAa\tfalse'));
      expect(content, isNot(contains('K2')));
    });

    test('empty translated text falls back to source text', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'K1',
              sourceText: 'Source',
              sourceLocFile: 'text/db/a.loc',
            ),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u1',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u1',
            translatedText: '',
          )));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      final content =
          await File(result.unwrap().first.tsvPath).readAsString();
      expect(content, contains('K1\tSource\tfalse'));
    });

    test('escapes tabs, newlines and backslashes in TSV text', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'K1',
              sourceText: 'x',
              sourceLocFile: 'text/db/a.loc',
            ),
          ]));
      when(() => versionRepo.getByUnitAndProjectLanguage(
            unitId: 'u1',
            projectLanguageId: projectLanguageId,
          )).thenAnswer((_) async => Ok(buildVersion(
            unitId: 'u1',
            translatedText: 'a\tb\nc\\d\r',
          )));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      final content =
          await File(result.unwrap().first.tsvPath).readAsString();
      // backslash -> \\ , tab -> \\t , newline -> \\n , \r removed.
      expect(content, contains(r'K1	a\\tb\\nc\\d	false'));
    });

    test('returns Err when no translation units exist', () async {
      when(() => unitRepo.getActive(projectId))
          .thenAnswer((_) async => Ok(<TranslationUnit>[]));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message,
          contains('No translation units found'));
    });

    test('returns Err when all units excluded leaving nothing', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(id: 'u1', key: 'DROP', sourceText: 'A'),
          ]));
      stubNoVersions();

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
        excludeKeys: {'DROP'},
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message,
          contains('No translations available for export'));
    });

    test('returns Err when project languages load fails', () async {
      when(() => projectLanguageRepo.getByProject(projectId)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('boom')));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('project languages'));
    });

    test('returns Err when language not in project', () async {
      when(() => projectLanguageRepo.getByProject(projectId)).thenAnswer(
          (_) async => Ok([buildProjectLanguage(langId: 'lang_other')]));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('not found in project'));
    });

    test('returns Err when units load fails', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer(
          (_) async => Err(TWMTDatabaseException('db down')));

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('translation units'));
    });

    test('uses custom prefix in generated internal path', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'K1',
              sourceText: 'A',
              sourceLocFile: 'text/db/a.loc',
            ),
          ]));
      stubNoVersions();

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
        prefix: 'zzz',
      );

      expect(result.unwrap().first.internalPath,
          'text/db/zzz_fr_twmt_a.loc');
    });

    test('uses default pack prefix constant by default', () async {
      when(() => unitRepo.getActive(projectId)).thenAnswer((_) async => Ok([
            buildUnit(
              id: 'u1',
              key: 'K1',
              sourceText: 'A',
              sourceLocFile: 'text/db/a.loc',
            ),
          ]));
      stubNoVersions();

      final result = await service.generateLocFilesGroupedBySource(
        projectId: projectId,
        languageCode: languageCode,
        validatedOnly: false,
      );

      expect(
        result.unwrap().first.internalPath,
        contains(AppConstants.defaultPackPrefix),
      );
    });
  });
}
