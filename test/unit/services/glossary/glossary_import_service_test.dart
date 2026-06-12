import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/models/domain/glossary_entry.dart';
import 'package:twmt/repositories/glossary_repository.dart';
import 'package:twmt/services/glossary/glossary_import_service.dart';
import 'package:twmt/services/glossary/i_glossary_service.dart';
import 'package:twmt/services/glossary/models/glossary.dart';
import 'package:twmt/services/glossary/models/glossary_exceptions.dart';

import '../../../helpers/fakes/fake_logger.dart';

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

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('glossary_import_test');
    repo = _MockRepo();
    glossaryService = _MockGlossaryService();
    service = GlossaryImportService(repo, glossaryService, logger: FakeLogger());

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

  File _write(String name, String content) {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    f.writeAsStringSync(content);
    return f;
  }

  group('importFromCsv', () {
    test('returns NotFound when the glossary is missing', () async {
      when(() => repo.getGlossaryById('g1')).thenAnswer((_) async => null);
      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: 'x.csv', targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryNotFoundException>());
    });

    test('returns a file error when the file does not exist', () async {
      final r = await service.importFromCsv(
          glossaryId: 'g1',
          filePath: '${tmp.path}/missing.csv',
          targetLanguageCode: 'fr');
      expect(r.unwrapErr(), isA<GlossaryFileException>());
    });

    test('imports valid rows, skipping the header, blanks and bad rows',
        () async {
      final csv = _write('g.csv',
          'source,target,notes\r\nEmpire,Empire FR,a note\r\nLord,Seigneur\r\n,onlytarget\r\nSingle\r\n');

      final r = await service.importFromCsv(
          glossaryId: 'g1', filePath: csv.path, targetLanguageCode: 'fr');

      // Empire + Lord import; empty-source row and single-column row are skipped.
      expect(r.unwrap(), 2);
      verify(() => glossaryService.addEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            targetTerm: any(named: 'targetTerm'),
            caseSensitive: any(named: 'caseSensitive'),
            notes: any(named: 'notes'),
          )).called(2);
    });

    test('skips duplicates flagged by the repository', () async {
      when(() => repo.findDuplicateEntry(
            glossaryId: any(named: 'glossaryId'),
            targetLanguageCode: any(named: 'targetLanguageCode'),
            sourceTerm: any(named: 'sourceTerm'),
            caseSensitive: any(named: 'caseSensitive'),
          )).thenAnswer((_) async => _entry());

      final csv = _write('g.csv', 'source,target\r\nEmpire,Empire FR\r\n');
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
  });

  group('importFromTbx', () {
    String tbx(String body) =>
        '<?xml version="1.0"?>\n<martif xml:lang="en"><text><body>$body</body></text></martif>';

    test('rejects invalid XML', () async {
      final f = _write('g.tbx', 'not xml <<<');
      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrapErr(), isA<GlossaryFileException>());
    });

    test('rejects a file without a martif root', () async {
      final f = _write('g.tbx', '<?xml version="1.0"?>\n<root/>');
      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);
      expect(r.unwrapErr(), isA<GlossaryFileException>());
    });

    test('parses term entries and imports one target per non-source langSet',
        () async {
      final f = _write(
        'g.tbx',
        tbx('''
<termEntry id="t1">
  <langSet xml:lang="en"><tig><term>Empire</term></tig></langSet>
  <langSet xml:lang="fr"><tig><term>Empire FR</term></tig></langSet>
  <langSet xml:lang="de"><tig><term>Reich</term></tig></langSet>
</termEntry>'''),
      );

      final r = await service.importFromTbx(glossaryId: 'g1', filePath: f.path);

      // Source = en; two non-source langSets (fr, de) -> two imported entries.
      expect(r.unwrap(), 2);
    });
  });
}
