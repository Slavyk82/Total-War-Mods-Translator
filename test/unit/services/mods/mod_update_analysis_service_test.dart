import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/mod_update_analysis.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/file/i_localization_parser.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/mods/mod_update_analysis_service.dart';
import 'package:twmt/services/rpfm/i_rpfm_service.dart';
import 'package:twmt/services/rpfm/models/rpfm_exceptions.dart';
import 'package:twmt/services/rpfm/models/rpfm_extract_result.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRpfm extends Mock implements IRpfmService {}

class _MockParser extends Mock implements ILocalizationParser {}

class _MockUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockLangRepo extends Mock implements ProjectLanguageRepository {}

TranslationUnit _unit(String key, String source) => TranslationUnit(
      id: 'id-$key',
      projectId: 'p',
      key: key,
      sourceText: source,
      createdAt: 0,
      updatedAt: 0,
    );

RpfmExtractResult _extract(List<String> files) => RpfmExtractResult(
      packFilePath: 'mod.pack',
      outputDirectory: 'C:/nope/rpfm_x', // non-existent -> cleanup is a no-op
      extractedFiles: files,
      localizationFileCount: files.length,
      totalSizeBytes: 0,
      durationMs: 0,
      timestamp: DateTime(2026, 1, 1),
    );

LocalizationFile _locFile(Map<String, String> entries) => LocalizationFile(
      fileName: 'a.loc',
      filePath: 'a.loc',
      languageCode: 'en',
      entries:
          entries.entries.map((e) => LocalizationEntry(key: e.key, value: e.value)).toList(),
    );

Ok<T, TWMTDatabaseException> _ok<T>(T v) => Ok(v);
Err<T, TWMTDatabaseException> _dbErr<T>(String m) => Err(TWMTDatabaseException(m));

ModUpdateAnalysis _analysis({
  int modified = 0,
  int removed = 0,
  int newU = 0,
  int reactivated = 0,
  List<String> modifiedKeys = const [],
  Map<String, String> modifiedTexts = const {},
  List<String> removedKeys = const [],
  List<String> reactivatedKeys = const [],
  Map<String, String> reactivatedTexts = const {},
  List<NewUnitData> newData = const [],
}) =>
    ModUpdateAnalysis(
      newUnitsCount: newU,
      removedUnitsCount: removed,
      modifiedUnitsCount: modified,
      reactivatedUnitsCount: reactivated,
      totalPackUnits: 0,
      totalProjectUnits: 0,
      modifiedUnitKeys: modifiedKeys,
      modifiedSourceTexts: modifiedTexts,
      removedUnitKeys: removedKeys,
      reactivatedUnitKeys: reactivatedKeys,
      reactivatedSourceTexts: reactivatedTexts,
      newUnitsData: newData,
    );

void main() {
  late _MockRpfm rpfm;
  late _MockParser parser;
  late _MockUnitRepo unitRepo;
  late _MockVersionRepo versionRepo;
  late _MockLangRepo langRepo;
  late ModUpdateAnalysisService service;

  setUp(() {
    rpfm = _MockRpfm();
    parser = _MockParser();
    unitRepo = _MockUnitRepo();
    versionRepo = _MockVersionRepo();
    langRepo = _MockLangRepo();
    service = ModUpdateAnalysisService(
      rpfmService: rpfm,
      locParser: parser,
      unitRepository: unitRepo,
      versionRepository: versionRepo,
      languageRepository: langRepo,
      logger: FakeLogger(),
      activityLogger: null,
    );
  });

  group('analyzeChanges', () {
    test('propagates an error when active units cannot be loaded', () async {
      when(() => unitRepo.getActive('p'))
          .thenAnswer((_) async => _dbErr<List<TranslationUnit>>('boom'));

      final r = await service.analyzeChanges(projectId: 'p', packFilePath: 'm');
      expect(r.isErr, isTrue);
    });

    test('propagates an error when extraction fails', () async {
      when(() => unitRepo.getActive('p')).thenAnswer((_) async => _ok([]));
      when(() => unitRepo.getObsolete('p')).thenAnswer((_) async => _ok([]));
      when(() => rpfm.extractLocalizationFilesAsTsv(any(),
              outputDirectory: any(named: 'outputDirectory'),
              schemaPath: any(named: 'schemaPath')))
          .thenAnswer((_) async => Err(_rpfmErr()));

      final r = await service.analyzeChanges(projectId: 'p', packFilePath: 'm');
      expect(r.isErr, isTrue);
    });

    test('classifies new, modified, removed and reactivated keys', () async {
      // Existing active: A (old text), B (same), E (will be removed).
      when(() => unitRepo.getActive('p')).thenAnswer((_) async => _ok([
            _unit('A', 'old-A'),
            _unit('B', 'B-text'),
            _unit('E', 'E-text'),
          ]));
      // Obsolete: C (reappears in pack).
      when(() => unitRepo.getObsolete('p'))
          .thenAnswer((_) async => _ok([_unit('C', 'C-old')]));

      when(() => rpfm.extractLocalizationFilesAsTsv(any(),
              outputDirectory: any(named: 'outputDirectory'),
              schemaPath: any(named: 'schemaPath')))
          .thenAnswer((_) async => Ok(_extract(['C:/nope/rpfm_x/text/db/a.loc.tsv'])));
      // Pack: A changed, B same, C reappears, D new.
      when(() => parser.parseFile(
            filePath: any(named: 'filePath'),
            encoding: any(named: 'encoding'),
          )).thenAnswer((_) async => Ok(_locFile({
            'A': 'new-A',
            'B': 'B-text',
            'C': 'C-new',
            'D': 'D-text',
          })));

      final analysis =
          (await service.analyzeChanges(projectId: 'p', packFilePath: 'm')).unwrap();

      expect(analysis.modifiedUnitKeys, ['A']);
      expect(analysis.modifiedSourceTexts['A'], 'new-A');
      expect(analysis.removedUnitKeys, ['E']);
      expect(analysis.reactivatedUnitKeys, ['C']);
      expect(analysis.newUnitKeys, ['D']);
      expect(analysis.totalPackUnits, 4);
    });
  });

  group('applyModifiedSourceTexts', () {
    test('is a no-op when there are no modified units', () async {
      final r = await service.applyModifiedSourceTexts(
          projectId: 'p', analysis: _analysis(modified: 0));

      final out = r.unwrap();
      expect(out.sourceTextsUpdated, 0);
      expect(out.translationsReset, 0);
      verifyNever(() => versionRepo.resetStatusForUnitKeys(
          projectId: any(named: 'projectId'),
          unitKeys: any(named: 'unitKeys'),
          onProgress: any(named: 'onProgress')));
    });

    test('resets statuses then updates source texts, returning both counts',
        () async {
      when(() => versionRepo.resetStatusForUnitKeys(
            projectId: any(named: 'projectId'),
            unitKeys: any(named: 'unitKeys'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => _ok(3));
      when(() => unitRepo.updateSourceTexts(
            projectId: any(named: 'projectId'),
            sourceTextUpdates: any(named: 'sourceTextUpdates'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => _ok(2));

      final r = await service.applyModifiedSourceTexts(
        projectId: 'p',
        analysis: _analysis(
            modified: 2,
            modifiedKeys: ['A', 'B'],
            modifiedTexts: {'A': 'x', 'B': 'y'}),
      );

      final out = r.unwrap();
      expect(out.translationsReset, 3);
      expect(out.sourceTextsUpdated, 2);
    });

    test('propagates a reset failure without updating source texts', () async {
      when(() => versionRepo.resetStatusForUnitKeys(
            projectId: any(named: 'projectId'),
            unitKeys: any(named: 'unitKeys'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => _dbErr<int>('reset failed'));

      final r = await service.applyModifiedSourceTexts(
        projectId: 'p',
        analysis: _analysis(modified: 1, modifiedKeys: ['A'], modifiedTexts: {'A': 'x'}),
      );

      expect(r.isErr, isTrue);
      verifyNever(() => unitRepo.updateSourceTexts(
          projectId: any(named: 'projectId'),
          sourceTextUpdates: any(named: 'sourceTextUpdates'),
          onProgress: any(named: 'onProgress')));
    });
  });

  group('markRemovedUnitsObsolete', () {
    test('is a no-op when nothing was removed', () async {
      expect((await service.markRemovedUnitsObsolete(
              projectId: 'p', analysis: _analysis(removed: 0)))
          .unwrap(), 0);
    });

    test('delegates to the repository and returns the count', () async {
      when(() => unitRepo.markObsoleteByKeys(
            projectId: any(named: 'projectId'),
            keys: any(named: 'keys'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => _ok(4));

      final r = await service.markRemovedUnitsObsolete(
          projectId: 'p',
          analysis: _analysis(removed: 4, removedKeys: ['a', 'b', 'c', 'd']));
      expect(r.unwrap(), 4);
    });
  });

  group('reactivateObsoleteUnits', () {
    test('is a no-op when nothing was reactivated', () async {
      final r = await service.reactivateObsoleteUnits(
          projectId: 'p', analysis: _analysis(reactivated: 0));
      expect(r.unwrap().unitsReactivated, 0);
    });

    test('reactivates units and marks their translations for review', () async {
      when(() => unitRepo.reactivateByKeys(
            projectId: any(named: 'projectId'),
            sourceTextUpdates: any(named: 'sourceTextUpdates'),
            onProgress: any(named: 'onProgress'),
          )).thenAnswer((_) async => _ok(2));
      when(() => versionRepo.setNeedsReviewForUnitKeys(
            projectId: any(named: 'projectId'),
            unitKeys: any(named: 'unitKeys'),
          )).thenAnswer((_) async => _ok(5));

      final r = await service.reactivateObsoleteUnits(
        projectId: 'p',
        analysis: _analysis(
            reactivated: 2,
            reactivatedKeys: ['C', 'F'],
            reactivatedTexts: {'C': 'c', 'F': 'f'}),
      );

      final out = r.unwrap();
      expect(out.unitsReactivated, 2);
      expect(out.translationsMarkedForReview, 5);
    });
  });

  group('addNewUnits (pre-transaction branches)', () {
    test('is a no-op when there are no new units', () async {
      expect(
        (await service.addNewUnits(projectId: 'p', analysis: _analysis(newU: 0)))
            .unwrap(),
        0,
      );
    });

    test('propagates a project-languages lookup failure', () async {
      when(() => langRepo.getByProject('p'))
          .thenAnswer((_) async => _dbErr('lang boom'));

      final r = await service.addNewUnits(
        projectId: 'p',
        analysis: _analysis(
            newU: 1,
            newData: const [NewUnitData(key: 'D', sourceText: 'd')]),
      );
      expect(r.isErr, isTrue);
    });
  });
}

RpfmServiceException _rpfmErr() => RpfmServiceException('extract failed');
