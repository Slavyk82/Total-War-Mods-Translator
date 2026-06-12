import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/features/translation_editor/services/pack_import_service.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/localization_parser_impl.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';

import '../../../helpers/noop_logger.dart';

class MockRpfmService extends Mock implements IRpfmService {}

class MockLocalizationParser extends Mock implements LocalizationParserImpl {}

class MockUnitRepository extends Mock implements TranslationUnitRepository {}

class MockVersionRepository extends Mock
    implements TranslationVersionRepository {}

class MockProjectLanguageRepository extends Mock
    implements ProjectLanguageRepository {}

TranslationUnit _unit(String id, String key) => TranslationUnit(
      id: id,
      projectId: 'proj',
      key: key,
      sourceText: 'src-$key',
      createdAt: 0,
      updatedAt: 0,
    );

TranslationVersion _version(String id, String unitId, {String? text}) =>
    TranslationVersion(
      id: id,
      unitId: unitId,
      projectLanguageId: 'pl1',
      translatedText: text,
      createdAt: 0,
      updatedAt: 0,
    );

ProjectLanguage _projectLanguage() => ProjectLanguage(
      id: 'pl1',
      projectId: 'proj',
      languageId: 'lang_fr',
      createdAt: 0,
      updatedAt: 0,
    );

LocalizationEntry _entry(String key, String value) =>
    LocalizationEntry(key: key, value: value);

LocalizationFile _locFile(List<LocalizationEntry> entries) => LocalizationFile(
      fileName: 'f.loc',
      filePath: 'f.loc',
      languageCode: 'fr',
      entries: entries,
    );

void main() {
  // ---- Pure model getters -------------------------------------------------

  group('PackImportEntry getters', () {
    test('hasExistingTranslation reflects a non-empty existing version', () {
      final withText = PackImportEntry(
        unit: _unit('u1', 'k1'),
        existingVersion: _version('v1', 'u1', text: 'Bonjour'),
        importedValue: 'Salut',
        key: 'k1',
      );
      expect(withText.hasExistingTranslation, isTrue);
      expect(withText.existingTranslation, 'Bonjour');
      expect(withText.valuesDiffer, isTrue);
    });

    test('treats null and empty existing translations as absent', () {
      final none = PackImportEntry(
        unit: _unit('u1', 'k1'),
        existingVersion: null,
        importedValue: 'Salut',
        key: 'k1',
      );
      final empty = PackImportEntry(
        unit: _unit('u2', 'k2'),
        existingVersion: _version('v2', 'u2', text: ''),
        importedValue: 'Salut',
        key: 'k2',
      );
      expect(none.hasExistingTranslation, isFalse);
      expect(none.valuesDiffer, isFalse);
      expect(empty.hasExistingTranslation, isFalse);
    });

    test('valuesDiffer is false when existing equals imported', () {
      final same = PackImportEntry(
        unit: _unit('u1', 'k1'),
        existingVersion: _version('v1', 'u1', text: 'Salut'),
        importedValue: 'Salut',
        key: 'k1',
      );
      expect(same.valuesDiffer, isFalse);
    });
  });

  group('PackImportPreview / PackImportResult getters', () {
    test('partitions matching entries by conflict', () {
      final conflict = PackImportEntry(
        unit: _unit('u1', 'k1'),
        existingVersion: _version('v1', 'u1', text: 'Existing'),
        importedValue: 'New',
        key: 'k1',
      );
      final fresh = PackImportEntry(
        unit: _unit('u2', 'k2'),
        existingVersion: null,
        importedValue: 'New2',
        key: 'k2',
      );
      final preview = PackImportPreview(
        matchingEntries: [conflict, fresh],
        unmatchedEntries: [_entry('k3', 'v3')],
        totalEntriesInPack: 3,
        packFilePath: 'x.pack',
      );

      expect(preview.matchingCount, 2);
      expect(preview.unmatchedCount, 1);
      expect(preview.entriesWithConflicts, [conflict]);
      expect(preview.entriesWithoutConflicts, [fresh]);
    });

    test('PackImportResult aggregates counts', () {
      const result = PackImportResult(
        importedCount: 5,
        skippedCount: 2,
        errorCount: 1,
        errors: ['oops'],
      );
      expect(result.hasErrors, isTrue);
      expect(result.totalProcessed, 8);
    });
  });

  // ---- Service flows ------------------------------------------------------

  group('PackImportService', () {
    late MockRpfmService rpfm;
    late MockLocalizationParser parser;
    late MockUnitRepository unitRepo;
    late MockVersionRepository versionRepo;
    late MockProjectLanguageRepository projectLangRepo;
    late PackImportService service;
    late Directory tempRoot;

    setUpAll(() {
      registerFallbackValue(<TranslationVersion>[]);
      registerFallbackValue(<String, String>{});
    });

    setUp(() async {
      rpfm = MockRpfmService();
      parser = MockLocalizationParser();
      unitRepo = MockUnitRepository();
      versionRepo = MockVersionRepository();
      projectLangRepo = MockProjectLanguageRepository();
      service = PackImportService(
        rpfmService: rpfm,
        localizationParser: parser,
        unitRepository: unitRepo,
        versionRepository: versionRepo,
        projectLanguageRepository: projectLangRepo,
        logger: NoopLogger(),
      );
      tempRoot = await Directory.systemTemp.createTemp('pack_import_test_');

      when(() => projectLangRepo.getByProject('proj'))
          .thenAnswer((_) async => Ok([_projectLanguage()]));
    });

    tearDown(() async {
      if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
    });

    /// A real pack file path so the existence check passes.
    String makePack() {
      final p = '${tempRoot.path}/mod.pack';
      File(p).writeAsStringSync('PACK');
      return p;
    }

    RpfmExtractResult extractResult(List<String> files, String outDir) =>
        RpfmExtractResult(
          packFilePath: 'mod.pack',
          outputDirectory: outDir,
          extractedFiles: files,
          localizationFileCount: files.length,
          totalSizeBytes: 0,
          durationMs: 0,
          timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        );

    Future<Result<PackImportPreview, String>> preview(String pack) =>
        service.previewImport(
          packFilePath: pack,
          projectId: 'proj',
          languageId: 'lang_fr',
        );

    group('previewImport', () {
      test('fails when the pack file does not exist', () async {
        final result = await preview('${tempRoot.path}/missing.pack');
        expect((result as Err).error, contains('Pack file does not exist'));
      });

      test('fails when project languages cannot be retrieved', () async {
        when(() => projectLangRepo.getByProject('proj'))
            .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
        final result = await preview(makePack());
        expect((result as Err).error, contains('Failed to retrieve project'));
      });

      test('fails when the project language is not configured', () async {
        when(() => projectLangRepo.getByProject('proj'))
            .thenAnswer((_) async => const Ok(<ProjectLanguage>[]));
        final result = await preview(makePack());
        expect((result as Err).error, contains('Project language not found'));
      });

      test('fails when extraction errors', () async {
        when(() => rpfm.extractLocalizationFilesAsTsv(any())).thenAnswer(
          (_) async => Err(const RpfmExtractionException('cli down')),
        );
        final result = await preview(makePack());
        expect((result as Err).error, contains('Failed to extract pack'));
      });

      test('fails when no localization files are extracted', () async {
        when(() => rpfm.extractLocalizationFilesAsTsv(any())).thenAnswer(
          (_) async => Ok(extractResult([], tempRoot.path)),
        );
        final result = await preview(makePack());
        expect((result as Err).error, contains('No localization files found'));
      });

      test('fails when extracted files contain no entries', () async {
        final outDir = Directory('${tempRoot.path}/out')..createSync();
        when(() => rpfm.extractLocalizationFilesAsTsv(any())).thenAnswer(
          (_) async => Ok(extractResult(['a.tsv'], outDir.path)),
        );
        when(() => parser.parseFile(filePath: any(named: 'filePath')))
            .thenAnswer((_) async => Ok(_locFile([])));
        final result = await preview(makePack());
        expect((result as Err).error, contains('No localization entries'));
      });

      test('matches pack entries against project units', () async {
        final outDir = Directory('${tempRoot.path}/out')..createSync();
        when(() => rpfm.extractLocalizationFilesAsTsv(any())).thenAnswer(
          (_) async => Ok(extractResult(['a.tsv'], outDir.path)),
        );
        when(() => parser.parseFile(filePath: any(named: 'filePath')))
            .thenAnswer((_) async => Ok(_locFile([
                  _entry('k1', 'Imported1'),
                  _entry('unknown', 'Orphan'),
                ])));
        when(() => unitRepo.getByProject('proj'))
            .thenAnswer((_) async => Ok([_unit('u1', 'k1')]));
        when(() => versionRepo.getByProjectLanguage('pl1'))
            .thenAnswer((_) async => Ok([_version('v1', 'u1', text: 'Old')]));

        final result = await preview(makePack());
        final p = (result as Ok<PackImportPreview, String>).value;

        expect(p.totalEntriesInPack, 2);
        expect(p.matchingCount, 1);
        expect(p.unmatchedCount, 1);
        expect(p.matchingEntries.single.importedValue, 'Imported1');
        expect(p.matchingEntries.single.existingVersion?.id, 'v1');
        // Temp extraction dir is cleaned up.
        expect(await outDir.exists(), isFalse);
      });

      test('fails when translation units cannot be retrieved', () async {
        final outDir = Directory('${tempRoot.path}/out')..createSync();
        when(() => rpfm.extractLocalizationFilesAsTsv(any())).thenAnswer(
          (_) async => Ok(extractResult(['a.tsv'], outDir.path)),
        );
        when(() => parser.parseFile(filePath: any(named: 'filePath')))
            .thenAnswer((_) async => Ok(_locFile([_entry('k1', 'v')])));
        when(() => unitRepo.getByProject('proj'))
            .thenAnswer((_) async => Err(TWMTDatabaseException('db')));
        final result = await preview(makePack());
        expect((result as Err).error, contains('Failed to retrieve translation units'));
      });
    });

    group('executeImport', () {
      PackImportEntry entry(String unitId, String key,
              {TranslationVersion? existing, String value = 'New'}) =>
          PackImportEntry(
            unit: _unit(unitId, key),
            existingVersion: existing,
            importedValue: value,
            key: key,
          );

      test('fails when the project language is not configured', () async {
        when(() => projectLangRepo.getByProject('proj'))
            .thenAnswer((_) async => const Ok(<ProjectLanguage>[]));
        final result = await service.executeImport(
          entriesToImport: [entry('u1', 'k1')],
          projectId: 'proj',
          languageId: 'lang_fr',
        );
        expect((result as Err).error, contains('Project language not found'));
      });

      test('skips everything when overwrite disabled and all have existing',
          () async {
        final result = await service.executeImport(
          entriesToImport: [
            entry('u1', 'k1', existing: _version('v1', 'u1', text: 'Old')),
          ],
          projectId: 'proj',
          languageId: 'lang_fr',
          overwriteExisting: false,
        );
        final r = (result as Ok<PackImportResult, String>).value;
        expect(r.importedCount, 0);
        expect(r.skippedCount, 1);
        verifyNever(() => versionRepo.importTranslations(
              entities: any(named: 'entities'),
              existingVersionIds: any(named: 'existingVersionIds'),
              onProgress: any(named: 'onProgress'),
              isCancelled: any(named: 'isCancelled'),
            ));
      });

      test('builds new and updated versions and reports counts', () async {
        when(() => versionRepo.importTranslations(
              entities: any(named: 'entities'),
              existingVersionIds: any(named: 'existingVersionIds'),
              onProgress: any(named: 'onProgress'),
              isCancelled: any(named: 'isCancelled'),
            )).thenAnswer(
          (_) async => const Ok((inserted: 1, updated: 1, skipped: 0)),
        );

        final progress = <int>[];
        final result = await service.executeImport(
          entriesToImport: [
            entry('u1', 'k1'), // new
            entry('u2', 'k2',
                existing: _version('v2', 'u2', text: 'Old')), // update
          ],
          projectId: 'proj',
          languageId: 'lang_fr',
          onProgress: (c, t, m) => progress.add(c),
        );

        final r = (result as Ok<PackImportResult, String>).value;
        expect(r.importedCount, 2);
        expect(r.errorCount, 0);
        expect(progress, isNotEmpty);

        final captured = verify(() => versionRepo.importTranslations(
              entities: captureAny(named: 'entities'),
              existingVersionIds: captureAny(named: 'existingVersionIds'),
              onProgress: any(named: 'onProgress'),
              isCancelled: any(named: 'isCancelled'),
            )).captured;
        final entities = captured[0] as List<TranslationVersion>;
        final existingIds = captured[1] as Map<String, String>;
        expect(entities, hasLength(2));
        // The updated entry maps unit -> existing version id.
        expect(existingIds['u2'], 'v2');
      });

      test('wraps an import repository failure', () async {
        when(() => versionRepo.importTranslations(
              entities: any(named: 'entities'),
              existingVersionIds: any(named: 'existingVersionIds'),
              onProgress: any(named: 'onProgress'),
              isCancelled: any(named: 'isCancelled'),
            )).thenAnswer((_) async => Err(TWMTDatabaseException('boom')));

        final result = await service.executeImport(
          entriesToImport: [entry('u1', 'k1')],
          projectId: 'proj',
          languageId: 'lang_fr',
        );
        expect((result as Err).error, contains('Import failed'));
      });
    });
  });
}
