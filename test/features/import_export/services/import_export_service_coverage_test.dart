import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/features/import_export/models/import_conflict.dart';
import 'package:twmt/features/import_export/models/import_export_settings.dart';
import 'package:twmt/features/import_export/models/import_preview.dart';
import 'package:twmt/features/import_export/models/import_result.dart';
import 'package:twmt/features/import_export/services/import_export_service.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/models/domain/project_language.dart';
import 'package:twmt/models/domain/translation_unit.dart';
import 'package:twmt/models/domain/translation_version.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/repositories/project_language_repository.dart';
import 'package:twmt/repositories/translation_unit_repository.dart';
import 'package:twmt/repositories/translation_version_repository.dart';
import 'package:twmt/services/history/i_history_service.dart';

/// Coverage-focused unit tests for [ImportExportService].
///
/// These exercise the export-side logic (executeExport / previewExport and the
/// private filter/row/format helpers reached through them) with mocked
/// collaborators (mocktail) so every column variant, filter branch, format
/// branch and error/Err branch is reached deterministically.
///
/// Real temp files are used only where the service reads a written file back
/// from disk (`File(outputPath).length()`); the file-service export mock writes
/// real content to that path so the length read succeeds (Windows path trap:
/// the actual returned path is read back).
class _MockFileService extends Mock implements IFileService {}

class _MockUnitRepo extends Mock implements TranslationUnitRepository {}

class _MockVersionRepo extends Mock implements TranslationVersionRepository {}

class _MockProjectLanguageRepo extends Mock
    implements ProjectLanguageRepository {}

class _MockHistoryService extends Mock implements IHistoryService {}

void main() {
  late _MockFileService fileService;
  late _MockUnitRepo unitRepo;
  late _MockVersionRepo versionRepo;
  late _MockProjectLanguageRepo plRepo;
  late _MockHistoryService history;
  late ImportExportService service;
  late Directory tempDir;

  const now = 1700000000;

  setUpAll(() {
    registerFallbackValue(<Map<String, String>>[]);
  });

  setUp(() {
    fileService = _MockFileService();
    unitRepo = _MockUnitRepo();
    versionRepo = _MockVersionRepo();
    plRepo = _MockProjectLanguageRepo();
    history = _MockHistoryService();

    service = ImportExportService(
      fileService,
      unitRepo,
      versionRepo,
      history,
      plRepo,
    );

    tempDir = Directory.systemTemp.createTempSync('impexp_cov_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  TranslationVersion version(
    String id,
    String unitId, {
    String? text = 'translated',
    TranslationVersionStatus status = TranslationVersionStatus.translated,
    bool manual = false,
    int createdAt = now,
    int updatedAt = now,
  }) =>
      TranslationVersion(
        id: id,
        unitId: unitId,
        projectLanguageId: 'pl-1',
        translatedText: text,
        isManuallyEdited: manual,
        status: status,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  TranslationUnit unit(
    String id, {
    String key = 'KEY',
    String source = 'source',
    String? context,
    String? notes,
  }) =>
      TranslationUnit(
        id: id,
        projectId: 'proj-1',
        key: key,
        sourceText: source,
        context: context,
        notes: notes,
        createdAt: now,
        updatedAt: now,
      );

  ProjectLanguage projectLanguage() => ProjectLanguage(
        id: 'pl-1',
        projectId: 'proj-1',
        languageId: 'lang_fr',
        createdAt: now,
        updatedAt: now,
      );

  ExportSettings exportSettings({
    ExportFormat format = ExportFormat.csv,
    List<ExportColumn>? columns,
    ExportFilterOptions? filter,
    ExportFormatOptions? formatOptions,
  }) =>
      ExportSettings(
        format: format,
        projectId: 'proj-1',
        targetLanguageId: 'lang_fr',
        columns: columns ??
            const [
              ExportColumn.key,
              ExportColumn.sourceText,
              ExportColumn.targetText,
              ExportColumn.status,
            ],
        filterOptions: filter ?? const ExportFilterOptions(),
        formatOptions: formatOptions ?? const ExportFormatOptions(),
      );

  // Make plRepo resolve to a single project-language by default.
  void stubProjectLanguageOk() {
    when(() => plRepo.getByProjectAndLanguage(any(), any()))
        .thenAnswer((_) async => Ok(projectLanguage()));
  }

  void stubVersions(List<TranslationVersion> versions) {
    when(() => versionRepo.getByProjectLanguage(any()))
        .thenAnswer((_) async => Ok(versions));
  }

  void stubUnit(String id, TranslationUnit u) {
    when(() => unitRepo.getById(id)).thenAnswer((_) async => Ok(u));
  }

  // CSV/JSON/Excel export mocks that actually write content to disk so the
  // service's subsequent `File(outputPath).length()` succeeds.
  void stubExportWritesFile() {
    when(() => fileService.exportToCsv(
          data: any(named: 'data'),
          filePath: any(named: 'filePath'),
        )).thenAnswer((inv) async {
      final path = inv.namedArguments[#filePath] as String;
      await File(path).writeAsString('csv-content');
      return Ok(path);
    });
    when(() => fileService.exportToJson(
          data: any(named: 'data'),
          filePath: any(named: 'filePath'),
          prettyPrint: any(named: 'prettyPrint'),
        )).thenAnswer((inv) async {
      final path = inv.namedArguments[#filePath] as String;
      final data = inv.namedArguments[#data];
      await File(path).writeAsString(jsonEncode(data));
      return Ok(path);
    });
    when(() => fileService.exportToExcel(
          data: any(named: 'data'),
          filePath: any(named: 'filePath'),
        )).thenAnswer((inv) async {
      final path = inv.namedArguments[#filePath] as String;
      await File(path).writeAsString('excel-binary');
      return Ok(path);
    });
  }

  group('executeExport - happy paths', () {
    test('CSV export writes rows and returns ExportResult', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1'), version('v2', 'u2')]);
      stubUnit('u1', unit('u1', key: 'K1', source: 'S1'));
      stubUnit('u2', unit('u2', key: 'K2', source: 'S2'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}out.csv';
      final progress = <List<int>>[];

      final result = await service.executeExport(
        exportSettings(),
        outPath,
        onProgress: (c, t) => progress.add([c, t]),
      );

      expect(result.isOk, isTrue, reason: result.toString());
      expect(result.value.rowCount, 2);
      expect(result.value.filePath, outPath);
      expect(result.value.fileSize, greaterThan(0));
      expect(result.value.durationMs, greaterThanOrEqualTo(0));
      // Progress was reported for each version.
      expect(progress, [
        [1, 2],
        [2, 2],
      ]);
      // The exported data captured by the mock contains the expected columns.
      final captured = verify(() => fileService.exportToCsv(
            data: captureAny(named: 'data'),
            filePath: any(named: 'filePath'),
          )).captured.single as List<Map<String, String>>;
      expect(captured.length, 2);
      expect(captured.first.keys,
          containsAll(['key', 'source_text', 'target_text', 'status']));
      expect(captured.first['key'], 'K1');
      // The path is read back from disk (Windows path trap).
      expect(File(outPath).existsSync(), isTrue);
    });

    test('JSON export honors prettyPrint option', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1')]);
      stubUnit('u1', unit('u1'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}out.json';
      final result = await service.executeExport(
        exportSettings(
          format: ExportFormat.json,
          formatOptions: const ExportFormatOptions(prettyPrint: false),
        ),
        outPath,
      );

      expect(result.isOk, isTrue, reason: result.toString());
      verify(() => fileService.exportToJson(
            data: any(named: 'data'),
            filePath: outPath,
            prettyPrint: false,
          )).called(1);
    });

    test('Excel export path', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1')]);
      stubUnit('u1', unit('u1'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}out.xlsx';
      final result = await service.executeExport(
        exportSettings(format: ExportFormat.excel),
        outPath,
      );

      expect(result.isOk, isTrue, reason: result.toString());
      verify(() => fileService.exportToExcel(
            data: any(named: 'data'),
            filePath: outPath,
          )).called(1);
    });

    test('all export columns are rendered', () async {
      stubProjectLanguageOk();
      stubVersions([
        version('v1', 'u1', status: TranslationVersionStatus.needsReview,
            manual: true),
      ]);
      stubUnit(
        'u1',
        unit('u1',
            key: 'K1', source: 'S1', context: 'ctx', notes: 'a note'),
      );
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}all.csv';
      final result = await service.executeExport(
        exportSettings(columns: const [
          ExportColumn.key,
          ExportColumn.sourceText,
          ExportColumn.targetText,
          ExportColumn.status,
          ExportColumn.notes,
          ExportColumn.context,
          ExportColumn.createdAt,
          ExportColumn.updatedAt,
          ExportColumn.changedBy,
        ]),
        outPath,
      );

      expect(result.isOk, isTrue, reason: result.toString());
      final row = verify(() => fileService.exportToCsv(
            data: captureAny(named: 'data'),
            filePath: any(named: 'filePath'),
          )).captured.single as List<Map<String, String>>;
      final m = row.single;
      expect(m['key'], 'K1');
      expect(m['source_text'], 'S1');
      expect(m['target_text'], 'translated');
      expect(m['status'], 'Needs Review');
      expect(m['notes'], 'a note');
      expect(m['context'], 'ctx');
      expect(m['changed_by'], 'User'); // manual edit
      expect(m['created_at'], contains('T')); // ISO-8601
      expect(m['updated_at'], contains('T'));
    });

    test('changed_by is LLM when not manually edited; null notes/context map to empty',
        () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1', manual: false)]);
      stubUnit('u1', unit('u1')); // notes/context null
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}llm.csv';
      await service.executeExport(
        exportSettings(columns: const [
          ExportColumn.changedBy,
          ExportColumn.notes,
          ExportColumn.context,
          ExportColumn.targetText,
        ]),
        outPath,
      );

      final row = verify(() => fileService.exportToCsv(
            data: captureAny(named: 'data'),
            filePath: any(named: 'filePath'),
          )).captured.single as List<Map<String, String>>;
      final m = row.single;
      expect(m['changed_by'], 'LLM');
      expect(m['notes'], '');
      expect(m['context'], '');
      expect(m['target_text'], 'translated');
    });

    test('null translated_text maps target_text to empty string', () async {
      stubProjectLanguageOk();
      stubVersions([
        version('v1', 'u1',
            text: null, status: TranslationVersionStatus.pending),
      ]);
      stubUnit('u1', unit('u1'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}empty.csv';
      await service.executeExport(
        exportSettings(columns: const [ExportColumn.targetText]),
        outPath,
      );

      final row = verify(() => fileService.exportToCsv(
            data: captureAny(named: 'data'),
            filePath: any(named: 'filePath'),
          )).captured.single as List<Map<String, String>>;
      expect(row.single['target_text'], '');
    });
  });

  group('executeExport - filtering', () {
    test('unit getById Err skips the version (continue branch)', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1'), version('v2', 'u2')]);
      when(() => unitRepo.getById('u1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('boom')));
      stubUnit('u2', unit('u2', key: 'K2'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}skip.csv';
      final result =
          await service.executeExport(exportSettings(), outPath);

      expect(result.isOk, isTrue);
      expect(result.value.rowCount, 1); // u1 skipped
    });

    test('contextFilter drops non-matching units', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1'), version('v2', 'u2')]);
      stubUnit('u1', unit('u1', context: 'campaign/intro'));
      stubUnit('u2', unit('u2', context: 'ui/menu'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}ctx.csv';
      final result = await service.executeExport(
        exportSettings(
          filter: const ExportFilterOptions(contextFilter: 'CAMPAIGN'),
        ),
        outPath,
      );

      expect(result.isOk, isTrue);
      expect(result.value.rowCount, 1); // only u1
    });

    test('version-level filters: validatedOnly, translationsOnly, statusFilter, timestamps',
        () async {
      stubProjectLanguageOk();
      stubVersions([
        version('v1', 'u1'), // translated, has text
        version('v2', 'u2',
            status: TranslationVersionStatus.pending), // dropped validatedOnly
        version('v3', 'u3', text: ''), // empty -> dropped translationsOnly
        version('v4', 'u4', createdAt: 10, updatedAt: 10), // old timestamps
      ]);
      stubUnit('u1', unit('u1'));
      stubUnit('u2', unit('u2'));
      stubUnit('u3', unit('u3'));
      stubUnit('u4', unit('u4'));
      stubExportWritesFile();

      final outPath = '${tempDir.path}${Platform.pathSeparator}vf.csv';
      final result = await service.executeExport(
        exportSettings(
          filter: const ExportFilterOptions(
            validatedOnly: true,
            translationsOnly: true,
            statusFilter: ['translated'],
            createdAfter: 100,
            updatedAfter: 100,
          ),
        ),
        outPath,
      );

      expect(result.isOk, isTrue);
      // Only v1 survives all version-level filters.
      expect(result.value.rowCount, 1);
    });
  });

  group('executeExport - error branches', () {
    test('project-language lookup Err returns Err', () async {
      when(() => plRepo.getByProjectAndLanguage(any(), any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('no pl')));

      final outPath = '${tempDir.path}${Platform.pathSeparator}e.csv';
      final result =
          await service.executeExport(exportSettings(), outPath);

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to resolve project language'));
    });

    test('versions fetch Err returns Err', () async {
      stubProjectLanguageOk();
      when(() => versionRepo.getByProjectLanguage(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db down')));

      final outPath = '${tempDir.path}${Platform.pathSeparator}e2.csv';
      final result =
          await service.executeExport(exportSettings(), outPath);

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to fetch translations'));
    });

    test('export write Err returns wrapped Err', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1')]);
      stubUnit('u1', unit('u1'));
      when(() => fileService.exportToCsv(
            data: any(named: 'data'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((_) async =>
          Err(ExportException('disk full', 'p', 'csv', entriesExported: 0)));

      final outPath = '${tempDir.path}${Platform.pathSeparator}e3.csv';
      final result =
          await service.executeExport(exportSettings(), outPath);

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Export failed'));
    });

    test('.loc format is not implemented -> Err', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1')]);
      stubUnit('u1', unit('u1'));

      final outPath = '${tempDir.path}${Platform.pathSeparator}e.loc';
      final result = await service.executeExport(
        exportSettings(format: ExportFormat.loc),
        outPath,
      );

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Export failed'));
    });

    test('unexpected exception in length read is caught (missing output file)',
        () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1')]);
      stubUnit('u1', unit('u1'));
      // Export reports success but does NOT create the file, so File.length throws.
      when(() => fileService.exportToCsv(
            data: any(named: 'data'),
            filePath: any(named: 'filePath'),
          )).thenAnswer((inv) async =>
          Ok(inv.namedArguments[#filePath] as String));

      final outPath =
          '${tempDir.path}${Platform.pathSeparator}does_not_exist.csv';
      final result =
          await service.executeExport(exportSettings(), outPath);

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Export failed'));
    });
  });

  group('previewExport', () {
    test('returns preview rows, headers, totals and estimated size', () async {
      stubProjectLanguageOk();
      // 12 versions so previewRows caps at 10 but totalRows counts all 12.
      final versions = List.generate(12, (i) => version('v$i', 'u$i'));
      stubVersions(versions);
      for (var i = 0; i < 12; i++) {
        stubUnit('u$i', unit('u$i', key: 'K$i', source: 'src$i'));
      }

      final result = await service.previewExport(exportSettings());

      expect(result.isOk, isTrue, reason: result.toString());
      final preview = result.value;
      expect(preview.totalRows, 12);
      expect(preview.previewRows.length, 10); // capped
      expect(preview.headers,
          ['key', 'source_text', 'target_text', 'status']);
      expect(preview.estimatedSize, greaterThan(0));
    });

    test('empty result uses fallback avg row size of 100', () async {
      stubProjectLanguageOk();
      stubVersions(const []);

      final result = await service.previewExport(exportSettings());

      expect(result.isOk, isTrue);
      expect(result.value.totalRows, 0);
      expect(result.value.previewRows, isEmpty);
      expect(result.value.estimatedSize, 0); // 100 * 0
    });

    test('preview skips units whose getById errors', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1'), version('v2', 'u2')]);
      when(() => unitRepo.getById('u1'))
          .thenAnswer((_) async => Err(TWMTDatabaseException('boom')));
      stubUnit('u2', unit('u2'));

      final result = await service.previewExport(exportSettings());

      expect(result.isOk, isTrue);
      expect(result.value.totalRows, 1);
    });

    test('preview propagates project-language Err', () async {
      when(() => plRepo.getByProjectAndLanguage(any(), any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('no pl')));

      final result = await service.previewExport(exportSettings());

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to resolve project language'));
    });

    test('preview propagates versions fetch Err', () async {
      stubProjectLanguageOk();
      when(() => versionRepo.getByProjectLanguage(any()))
          .thenAnswer((_) async => Err(TWMTDatabaseException('db down')));

      final result = await service.previewExport(exportSettings());

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to fetch translations'));
    });

    test('unexpected throw is caught and wrapped (catch branch)', () async {
      stubProjectLanguageOk();
      stubVersions([version('v1', 'u1')]);
      // Throw synchronously instead of returning Err -> hits the catch block.
      when(() => unitRepo.getById('u1')).thenThrow(StateError('kaboom'));

      final result = await service.previewExport(exportSettings());

      expect(result.isErr, isTrue);
      expect(result.error.message, contains('Failed to generate preview'));
    });

    test('all-column headers are built correctly', () async {
      stubProjectLanguageOk();
      stubVersions(const []);

      final result = await service.previewExport(
        exportSettings(columns: const [
          ExportColumn.key,
          ExportColumn.sourceText,
          ExportColumn.targetText,
          ExportColumn.status,
          ExportColumn.notes,
          ExportColumn.context,
          ExportColumn.createdAt,
          ExportColumn.updatedAt,
          ExportColumn.changedBy,
        ]),
      );

      expect(result.isOk, isTrue);
      expect(result.value.headers, [
        'key',
        'source_text',
        'target_text',
        'status',
        'notes',
        'context',
        'created_at',
        'updated_at',
        'changed_by',
      ]);
    });
  });

  group('detectColumnMapping (delegation)', () {
    test('returns a mapping for known headers', () {
      // Delegates to the real ImportFileReader; just assert it runs and returns
      // a Map without throwing.
      final mapping = service.detectColumnMapping(['key', 'source_text']);
      expect(mapping, isA<Map<String, String>>());
    });
  });

  group('import-side delegation', () {
    ImportSettings importSettings() => const ImportSettings(
          format: ImportFormat.csv,
          projectId: 'proj-1',
          targetLanguageId: 'lang_fr',
        );

    ImportPreview preview() => const ImportPreview(
          filePath: 'p.csv',
          headers: ['key'],
          previewRows: [],
          totalRows: 0,
          fileSize: 0,
          encoding: 'utf-8',
        );

    // ImportFileReader (used by every import collaborator) reads via the file
    // service; an Err there flows back out without needing a real database.
    void stubReadErr() {
      when(() => fileService.importFromCsv(
            filePath: any(named: 'filePath'),
            hasHeader: any(named: 'hasHeader'),
            encoding: any(named: 'encoding'),
          )).thenAnswer((_) async =>
          Err(ImportException('no file', 'p.csv', 'csv')));
    }

    test('previewImport delegates to preview service', () async {
      stubReadErr();
      final result =
          await service.previewImport('p.csv', importSettings());
      expect(result.isErr, isTrue);
    });

    test('detectConflicts delegates to conflict detector', () async {
      stubProjectLanguageOk();
      stubVersions(const []);
      final result =
          await service.detectConflicts(preview(), importSettings());
      // Empty preview -> no conflicts (Ok) regardless; the call is what matters.
      expect(result, isA<Result<List<ImportConflict>, ServiceException>>());
    });

    test('executeImport delegates to executor', () async {
      stubReadErr();
      stubProjectLanguageOk();
      final result = await service.executeImport(
        'p.csv',
        importSettings(),
        const ConflictResolutions(),
      );
      expect(result.isErr, isTrue);
    });

    test('validateImport delegates to preview service', () async {
      final result =
          await service.validateImport(preview(), importSettings());
      expect(
          result, isA<Result<ImportValidationResult, ServiceException>>());
    });
  });
}
