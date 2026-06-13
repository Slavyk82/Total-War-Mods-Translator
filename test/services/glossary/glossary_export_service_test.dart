import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';
import 'package:twmt/services/glossary/glossary_export_service.dart';
import 'package:xml/xml.dart';

import '../../helpers/noop_logger.dart';
import '../../helpers/test_bootstrap.dart';

class MockGlossaryRepository extends Mock implements GlossaryRepository {}

void main() {
  late MockGlossaryRepository repo;
  late GlossaryExportService service;
  late Directory tempDir;

  GlossaryEntry entry({
    String id = 'e1',
    String glossaryId = 'g1',
    String targetLanguageCode = 'fr',
    String sourceTerm = 'Sword',
    String targetTerm = 'Épée',
    bool caseSensitive = false,
    String? notes,
  }) {
    return GlossaryEntry(
      id: id,
      glossaryId: glossaryId,
      targetLanguageCode: targetLanguageCode,
      sourceTerm: sourceTerm,
      targetTerm: targetTerm,
      caseSensitive: caseSensitive,
      notes: notes,
      createdAt: 1000,
      updatedAt: 1000,
    );
  }

  Glossary glossary({String id = 'g1', String name = 'Warhammer'}) {
    return Glossary(
      id: id,
      name: name,
      gameCode: 'wh3',
      targetLanguageId: 'lang-fr',
      createdAt: 1000,
      updatedAt: 1000,
    );
  }

  setUp(() async {
    // The Excel export path constructs FileImportExportService() (the
    // singleton), which falls back to ServiceLocator.get<ILoggingService>().
    await TestBootstrap.registerFakes(logger: NoopLogger());
    repo = MockGlossaryRepository();
    service = GlossaryExportService(repo, logger: NoopLogger());
    tempDir = Directory.systemTemp.createTempSync('glossary_export_test_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  String pathIn(String name) => '${tempDir.path}${Platform.pathSeparator}$name';

  // ==========================================================================
  // CSV Export
  // ==========================================================================
  group('exportToCsv', () {
    test('writes header + rows and returns entry count', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            entry(sourceTerm: 'Sword', targetTerm: 'Epee', notes: 'weapon'),
            entry(id: 'e2', sourceTerm: 'Shield', targetTerm: 'Bouclier'),
          ]);

      final file = pathIn('out.csv');
      final result = await service.exportToCsv(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      expect(result.value, 2);

      final content = File(file).readAsStringSync();
      final rows = const CsvToListConverter(eol: '\r\n').convert(content);
      expect(rows.first, ['source_term', 'target_term', 'notes']);
      expect(rows[1], ['Sword', 'Epee', 'weapon']);
      // Missing notes serialize to empty string.
      expect(rows[2], ['Shield', 'Bouclier', '']);
    });

    test('escapes commas and quotes (RFC-4180 round trip)', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            entry(
              sourceTerm: 'Hello, "World"',
              targetTerm: 'Salut',
              notes: 'line1\nline2',
            ),
          ]);

      final file = pathIn('escaped.csv');
      final result = await service.exportToCsv(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      final content = File(file).readAsStringSync();
      // The embedded quote must be doubled and the field wrapped.
      expect(content, contains('"Hello, ""World"""'));

      // Round trip must preserve the original values.
      final rows = const CsvToListConverter(eol: '\r\n').convert(content);
      expect(rows[1][0], 'Hello, "World"');
      expect(rows[1][2], 'line1\nline2');
    });

    test('empty glossary writes header only and returns 0', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => []);

      final file = pathIn('empty.csv');
      final result = await service.exportToCsv(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      expect(result.value, 0);
      final rows =
          const CsvToListConverter(eol: '\r\n').convert(File(file).readAsStringSync());
      expect(rows, hasLength(1));
      expect(rows.first, ['source_term', 'target_term', 'notes']);
    });

    test('forwards targetLanguageCode filter to repository', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [entry()]);

      await service.exportToCsv(
        glossaryId: 'g1',
        filePath: pathIn('filter.csv'),
        targetLanguageCode: 'fr',
      );

      verify(() => repo.getEntriesByGlossary(
            glossaryId: 'g1',
            targetLanguageCode: 'fr',
          )).called(1);
    });

    test('returns Err GlossaryFileException when repository throws', () async {
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenThrow(Exception('db down'));

      final file = pathIn('err.csv');
      final result = await service.exportToCsv(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error;
      expect(err, isA<GlossaryFileException>());
      expect((err as GlossaryFileException).filePath, file);
      expect(err.message, contains('Failed to export CSV'));
    });
  });

  // ==========================================================================
  // TBX Export
  // ==========================================================================
  group('exportToTbx', () {
    test('writes valid TBX with langSets, notes and count', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary(name: 'My Glossary'));
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            entry(
              id: 'e1',
              sourceTerm: 'Sword',
              targetTerm: 'Epee',
              notes: 'a weapon',
              caseSensitive: true,
            ),
          ]);

      final file = pathIn('out.tbx');
      final result = await service.exportToTbx(
        glossaryId: 'g1',
        filePath: file,
        sourceLanguageCode: 'en',
        glossaryName: 'Custom Name',
      );

      expect(result.isOk, isTrue);
      expect(result.value, 1);

      final doc = XmlDocument.parse(File(file).readAsStringSync());
      final martif = doc.rootElement;
      expect(martif.name.local, 'martif');
      expect(martif.getAttribute('type'), 'TBX');
      expect(martif.getAttribute('xml:lang'), 'en');

      // Header uses the supplied glossaryName, not the glossary's own name.
      final sourceP =
          doc.findAllElements('sourceDesc').first.findElements('p').first;
      expect(sourceP.innerText, 'Custom Name');

      final termEntry = doc.findAllElements('termEntry').first;
      expect(termEntry.getAttribute('id'), 'e1');

      final langSets = termEntry.findElements('langSet').toList();
      expect(langSets, hasLength(2));
      expect(langSets[0].getAttribute('xml:lang'), 'en');
      expect(langSets[0].findAllElements('term').first.innerText, 'Sword');
      expect(langSets[1].getAttribute('xml:lang'), 'fr');
      expect(langSets[1].findAllElements('term').first.innerText, 'Epee');

      // Notes -> descrip type=context; caseSensitive -> descrip type=note.
      final descrips = termEntry.findAllElements('descrip').toList();
      final types = descrips.map((d) => d.getAttribute('type')).toList();
      expect(types, containsAll(['context', 'note']));
      final contextDescrip =
          descrips.firstWhere((d) => d.getAttribute('type') == 'context');
      expect(contextDescrip.innerText, 'a weapon');
    });

    test('omits notes/case descrip when entry has none', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            entry(notes: null, caseSensitive: false),
          ]);

      final file = pathIn('nonotes.tbx');
      final result = await service.exportToTbx(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      final doc = XmlDocument.parse(File(file).readAsStringSync());
      expect(doc.findAllElements('descrip'), isEmpty);
      // Default source language is 'en' when not supplied.
      expect(doc.rootElement.getAttribute('xml:lang'), 'en');
    });

    test('falls back to glossary.name in header when no glossaryName', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary(name: 'Fallback Name'));
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [entry()]);

      final file = pathIn('fallback.tbx');
      await service.exportToTbx(glossaryId: 'g1', filePath: file);

      final doc = XmlDocument.parse(File(file).readAsStringSync());
      final sourceP =
          doc.findAllElements('sourceDesc').first.findElements('p').first;
      expect(sourceP.innerText, 'Fallback Name');
    });

    test('escapes special XML characters in terms', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            entry(sourceTerm: 'A & B <tag>', targetTerm: '"quote"'),
          ]);

      final file = pathIn('special.tbx');
      await service.exportToTbx(glossaryId: 'g1', filePath: file);

      final raw = File(file).readAsStringSync();
      // The serializer escapes & and < (> is left as-is, which is valid XML).
      expect(raw, contains('A &amp; B &lt;tag>'));
      // Parsing must recover the original unescaped value.
      final doc = XmlDocument.parse(raw);
      final term = doc.findAllElements('term').first;
      expect(term.innerText, 'A & B <tag>');
    });

    test('returns GlossaryNotFoundException when glossary missing', () async {
      when(() => repo.getGlossaryById('missing'))
          .thenAnswer((_) async => null);

      final result = await service.exportToTbx(
        glossaryId: 'missing',
        filePath: pathIn('nf.tbx'),
      );

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<GlossaryNotFoundException>());
    });

    test('empty glossary returns Ok(0) and writes no file', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => []);

      final file = pathIn('empty.tbx');
      final result = await service.exportToTbx(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      expect(result.value, 0);
      expect(File(file).existsSync(), isFalse);
    });

    test('returns GlossaryFileException when repository throws', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenThrow(Exception('boom'));

      final file = pathIn('throw.tbx');
      final result = await service.exportToTbx(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error;
      expect(err, isA<GlossaryFileException>());
      expect(err.message, contains('Failed to export TBX'));
    });
  });

  // ==========================================================================
  // Excel Export
  // ==========================================================================
  group('exportToExcel', () {
    test('writes xlsx with header + rows and returns count', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary(name: 'Sheet Title'));
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [
            entry(sourceTerm: 'Sword', targetTerm: 'Epee', notes: 'weapon'),
            entry(id: 'e2', sourceTerm: 'Shield', targetTerm: 'Bouclier'),
          ]);

      final file = pathIn('out.xlsx');
      final result = await service.exportToExcel(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      expect(result.value, 2);
      expect(File(file).existsSync(), isTrue);

      final excel = Excel.decodeBytes(File(file).readAsBytesSync());
      // Sheet is named after the glossary.
      expect(excel.tables.keys, contains('Sheet Title'));
      final sheet = excel.tables['Sheet Title']!;
      final header =
          sheet.rows[0].map((c) => c?.value?.toString() ?? '').toList();
      expect(header, ['source_term', 'target_term', 'notes']);
      final firstRow =
          sheet.rows[1].map((c) => c?.value?.toString() ?? '').toList();
      expect(firstRow, ['Sword', 'Epee', 'weapon']);
      final secondRow =
          sheet.rows[2].map((c) => c?.value?.toString() ?? '').toList();
      expect(secondRow, ['Shield', 'Bouclier', '']);
    });

    test('returns GlossaryNotFoundException when glossary missing', () async {
      when(() => repo.getGlossaryById('missing'))
          .thenAnswer((_) async => null);

      final result = await service.exportToExcel(
        glossaryId: 'missing',
        filePath: pathIn('nf.xlsx'),
      );

      expect(result.isErr, isTrue);
      expect((result as Err).error, isA<GlossaryNotFoundException>());
    });

    test('empty glossary returns Ok(0) and writes no file', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => []);

      final file = pathIn('empty.xlsx');
      final result = await service.exportToExcel(
        glossaryId: 'g1',
        filePath: file,
      );

      expect(result.isOk, isTrue);
      expect(result.value, 0);
      expect(File(file).existsSync(), isFalse);
    });

    test('returns GlossaryFileException when file write fails', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenAnswer((_) async => glossary());
      when(() => repo.getEntriesByGlossary(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
          )).thenAnswer((_) async => [entry()]);

      // Point at a path whose parent is a file, forcing the underlying
      // FileImportExportService.exportToExcel to return Err.
      final blocker = File(pathIn('blocker'))..writeAsStringSync('x');
      final badPath =
          '${blocker.path}${Platform.pathSeparator}sub.xlsx';

      final result = await service.exportToExcel(
        glossaryId: 'g1',
        filePath: badPath,
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error;
      expect(err, isA<GlossaryFileException>());
      expect(err.message, contains('Failed to export Excel'));
    });

    test('returns GlossaryFileException when repository throws', () async {
      when(() => repo.getGlossaryById('g1'))
          .thenThrow(Exception('kaboom'));

      final result = await service.exportToExcel(
        glossaryId: 'g1',
        filePath: pathIn('throw.xlsx'),
      );

      expect(result.isErr, isTrue);
      final err = (result as Err).error;
      expect(err, isA<GlossaryFileException>());
      expect(err.message, contains('Failed to export Excel'));
    });
  });
}
