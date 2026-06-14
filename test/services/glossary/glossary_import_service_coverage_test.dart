import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_import_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

class _MockRepo extends Mock implements GlossaryRepository {}

class _MockGlossaryService extends Mock implements IGlossaryService {}

Glossary _glossary() => Glossary(
      id: 'g1',
      name: 'G',
      gameCode: 'wh3',
      targetLanguageId: 'fr-id',
      createdAt: 0,
      updatedAt: 0,
    );

GlossaryEntry _entry() => GlossaryEntry(
      id: 'e',
      glossaryId: 'g1',
      targetLanguageCode: 'fr',
      sourceTerm: 's',
      targetTerm: 't',
      createdAt: 0,
      updatedAt: 0,
    );

void main() {
  late Directory tmp;
  late _MockRepo repo;
  late _MockGlossaryService glossaryService;
  late GlossaryImportService service;

  setUpAll(() {
    registerFallbackValue(_entry());
  });

  setUp(() async {
    // The Excel import path constructs FileImportExportService() directly,
    // whose constructor resolves ILoggingService from the ServiceLocator.
    await TestBootstrap.registerFakes();

    tmp = Directory.systemTemp.createTempSync('glossary_import_cov_test');
    repo = _MockRepo();
    glossaryService = _MockGlossaryService();
    service = GlossaryImportService(repo, glossaryService, logger: NoopLogger());

    when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => _glossary());
    when(() => repo.findDuplicateEntry(
          glossaryId: any(named: 'glossaryId'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          sourceTerm: any(named: 'sourceTerm'),
          caseSensitive: any(named: 'caseSensitive'),
        )).thenAnswer((_) async => null);
    when(() => glossaryService.addEntry(
          glossaryId: any(named: 'glossaryId'),
          targetLanguageCode: any(named: 'targetLanguageCode'),
          sourceTerm: any(named: 'sourceTerm'),
          targetTerm: any(named: 'targetTerm'),
          caseSensitive: any(named: 'caseSensitive'),
          notes: any(named: 'notes'),
        )).thenAnswer((_) async => Ok(_entry()));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  String path(String name) => '${tmp.path}${Platform.pathSeparator}$name';

  File writeText(String name, String content) {
    final f = File(path(name));
    f.writeAsStringSync(content);
    return f;
  }

  /// Build a real .xlsx file with the given header + rows on 'Sheet1'.
  File writeXlsx(String name, List<List<String>> rowsOfCells) {
    final excel = Excel.createExcel();
    final sheet = excel['Sheet1'];
    for (final cells in rowsOfCells) {
      sheet.appendRow(cells.map<CellValue?>((c) => TextCellValue(c)).toList());
    }
    final bytes = excel.encode()!;
    final f = File(path(name));
    f.writeAsBytesSync(bytes);
    return f;
  }

  // ==========================================================================
  // CSV
  // ==========================================================================
  group('importFromCsv', () {
    test('returns Ok(0) for an empty file (no rows parsed)', () async {
      final csv = writeText('empty.csv', '');
      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: csv.path, targetLanguageCode: 'fr');
      expect(r.unwrap(), 0);
      verifyNever(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          ));
    });

    test('imports the third notes column as entry notes', () async {
      final csv =
          writeText('notes.csv', 'source,target,notes\r\nEmpire,Empire FR,ctx\r\n');
      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: csv.path, targetLanguageCode: 'fr');
      expect(r.unwrap(), 1);
      verify(() => glossaryService.addEntry(
            glossaryId: 'g1',
            targetLanguageCode: 'fr',
            sourceTerm: 'Empire',
            targetTerm: 'Empire FR',
            caseSensitive: false,
            notes: 'ctx',
          )).called(1);
    });

    test('does NOT pre-check duplicates when skipDuplicates is false', () async {
      // Even if a duplicate exists, with skipDuplicates=false the entry is added.
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry());

      final csv = writeText('dup.csv', 'source,target\r\nEmpire,Empire FR\r\n');
      final r = await service.importFromCsv(
          glossaryId: 'g1',
          filePath: csv.path,
          targetLanguageCode: 'fr',
          skipDuplicates: false);

      expect(r.unwrap(), 1);
      verifyNever(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          ));
      verify(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).called(1);
    });

    test('returns a file error when every data row fails to add', () async {
      when(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).thenAnswer(
          (_) async => Err(const GlossaryDatabaseException('boom')));

      final csv = writeText('g.csv', 'source,target\r\nEmpire,Empire FR\r\n');
      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: csv.path, targetLanguageCode: 'fr');

      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Import failed'));
    });

    test('still returns Ok when some rows fail but at least one succeeds',
        () async {
      var calls = 0;
      when(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async {
        calls++;
        return calls == 1
            ? Ok(_entry())
            : Err(const GlossaryDatabaseException('boom'));
      });

      final csv = writeText(
          'g.csv', 'source,target\r\nA,AA\r\nB,BB\r\n');
      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: csv.path, targetLanguageCode: 'fr');

      expect(r.unwrap(), 1);
    });

    test('wraps unexpected errors raised by the repository in a file error',
        () async {
      when(() => repo.getGlossaryById('g1')).thenThrow(StateError('db down'));
      final csv = writeText('g.csv', 'source,target\r\nA,AA\r\n');
      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: csv.path, targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Failed to import CSV'));
    });
  });

  // ==========================================================================
  // TBX
  // ==========================================================================
  group('importFromTbx', () {
    String tbx(String body, {String lang = 'en'}) =>
        '<?xml version="1.0"?>\n<martif xml:lang="$lang"><text><body>$body</body></text></martif>';

    test('returns NotFound when the glossary is missing', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final r = await service.importFromTbx(
          glossaryId: 'g1', filePath: path('x.tbx'));
      expect(r.unwrapErr(), isA<GlossaryNotFoundException>());
    });

    test('returns a file error when the TBX file does not exist', () async {
      final r = await service.importFromTbx(
          glossaryId: 'g1', filePath: path('missing.tbx'));
      expect(r.unwrapErr(), isA<GlossaryFileException>());
    });

    test('rejects a file with a martif root but no body element', () async {
      final f = writeText('nobody.tbx',
          '<?xml version="1.0"?>\n<martif xml:lang="en"><text></text></martif>');
      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('missing body'));
    });

    test('parses notes and the case-sensitive indicator from descripGrp',
        () async {
      final f = writeText(
        'g.tbx',
        tbx('''
<termEntry id="t1">
  <descripGrp><descrip type="note">case-sensitive</descrip></descripGrp>
  <descripGrp><descrip type="context">a helpful context</descrip></descripGrp>
  <langSet xml:lang="en"><tig><term>Empire</term></tig></langSet>
  <langSet xml:lang="fr"><tig><term>Empire FR</term></tig></langSet>
</termEntry>'''),
      );

      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);

      expect(r.unwrap(), 1);
      verify(() => glossaryService.addEntry(
            glossaryId: 'g1',
            targetLanguageCode: 'fr',
            sourceTerm: 'Empire',
            targetTerm: 'Empire FR',
            caseSensitive: true,
            notes: 'a helpful context',
          )).called(1);
    });

    test('stores a plain note-type descrip as entry notes', () async {
      // A 'note'-type descrip whose text is NOT the case-sensitive marker is
      // kept as free-form notes for LLM context.
      final f = writeText(
        'g.tbx',
        tbx('''
<termEntry id="t1">
  <descripGrp><descrip type="note">gender: masculine</descrip></descripGrp>
  <langSet xml:lang="en"><tig><term>Empire</term></tig></langSet>
  <langSet xml:lang="fr"><tig><term>Empire FR</term></tig></langSet>
</termEntry>'''),
      );

      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrap(), 1);
      verify(() => glossaryService.addEntry(
            glossaryId: 'g1',
            targetLanguageCode: 'fr',
            sourceTerm: 'Empire',
            targetTerm: 'Empire FR',
            caseSensitive: false,
            notes: 'gender: masculine',
          )).called(1);
    });

    test('skips duplicates flagged by the repository', () async {
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry());

      final f = writeText(
        'g.tbx',
        tbx('''
<termEntry id="t1">
  <langSet xml:lang="en"><tig><term>Empire</term></tig></langSet>
  <langSet xml:lang="fr"><tig><term>Empire FR</term></tig></langSet>
</termEntry>'''),
      );

      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrap(), 0);
      verifyNever(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          ));
    });

    test('returns a file error when every parsed entry fails to add', () async {
      when(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).thenAnswer(
          (_) async => Err(const GlossaryDatabaseException('boom')));

      final f = writeText(
        'g.tbx',
        tbx('''
<termEntry id="t1">
  <langSet xml:lang="en"><tig><term>Empire</term></tig></langSet>
  <langSet xml:lang="fr"><tig><term>Empire FR</term></tig></langSet>
</termEntry>'''),
      );

      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Import failed'));
    });

    test('imports zero entries from a body with no usable term entries',
        () async {
      // A termEntry with only a source langSet (no target) yields no entries.
      final f = writeText(
        'g.tbx',
        tbx('''
<termEntry id="t1">
  <langSet xml:lang="en"><tig><term>OnlySource</term></tig></langSet>
</termEntry>'''),
      );

      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrap(), 0);
    });

    test('wraps unexpected errors raised by the repository in a file error',
        () async {
      when(() => repo.getGlossaryById('g1')).thenThrow(StateError('db down'));
      final f = writeText('g.tbx', tbx(''));
      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Failed to import TBX'));
    });
  });

  // ==========================================================================
  // Excel
  // ==========================================================================
  group('importFromExcel', () {
    test('returns NotFound when the glossary is missing', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: path('x.xlsx'), targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryNotFoundException>());
    });

    test('returns a file error when the Excel file does not exist', () async {
      final r = await service.importFromExcel(
          glossaryId: 'g1',
          filePath: path('missing.xlsx'),
          targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryFileException>());
    });

    test('imports valid rows from a real .xlsx, including notes', () async {
      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term', 'notes'],
        ['Empire', 'Empire FR', 'ctx'],
        ['Lord', 'Seigneur', ''],
      ]);

      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: xlsx.path, targetLanguageCode: 'fr');

      expect(r.unwrap(), 2);
      verify(() => glossaryService.addEntry(
            glossaryId: 'g1',
            targetLanguageCode: 'fr',
            sourceTerm: 'Empire',
            targetTerm: 'Empire FR',
            caseSensitive: false,
            notes: 'ctx',
          )).called(1);
    });

    test('skips rows with an empty source or target term', () async {
      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term', 'notes'],
        ['', 'OnlyTarget', ''],
        ['OnlySource', '', ''],
        ['Lord', 'Seigneur', ''],
      ]);

      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: xlsx.path, targetLanguageCode: 'fr');

      expect(r.unwrap(), 1);
    });

    test('skips duplicates flagged by the repository', () async {
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry());

      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term'],
        ['Empire', 'Empire FR'],
      ]);

      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: xlsx.path, targetLanguageCode: 'fr');
      expect(r.unwrap(), 0);
      verifyNever(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          ));
    });

    test('does NOT pre-check duplicates when skipDuplicates is false', () async {
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry());

      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term'],
        ['Empire', 'Empire FR'],
      ]);

      final r = await service.importFromExcel(
          glossaryId: 'g1',
          filePath: xlsx.path,
          targetLanguageCode: 'fr',
          skipDuplicates: false);
      expect(r.unwrap(), 1);
      verifyNever(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          ));
    });

    test('returns Ok(0) when the sheet has only a header row', () async {
      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term'],
      ]);
      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: xlsx.path, targetLanguageCode: 'fr');
      expect(r.unwrap(), 0);
    });

    test('returns a file error when a named sheet is missing', () async {
      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term'],
        ['Empire', 'Empire FR'],
      ]);
      final r = await service.importFromExcel(
          glossaryId: 'g1',
          filePath: xlsx.path,
          targetLanguageCode: 'fr',
          sheetName: 'DoesNotExist');
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Failed to import Excel'));
    });

    test('returns a file error when every data row fails to add', () async {
      when(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).thenAnswer(
          (_) async => Err(const GlossaryDatabaseException('boom')));

      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term'],
        ['Empire', 'Empire FR'],
      ]);
      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: xlsx.path, targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Import failed'));
    });

    test('wraps unexpected errors raised by the repository in a file error',
        () async {
      when(() => repo.getGlossaryById('g1')).thenThrow(StateError('db down'));
      final xlsx = writeXlsx('g.xlsx', [
        ['source_term', 'target_term'],
        ['Empire', 'Empire FR'],
      ]);
      final r = await service.importFromExcel(
          glossaryId: 'g1', filePath: xlsx.path, targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryFileException>());
      expect(r.unwrapErr().message, contains('Failed to import Excel'));
    });
  });
}
