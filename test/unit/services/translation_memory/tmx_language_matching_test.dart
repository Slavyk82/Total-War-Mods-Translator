import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:twmt/repositories/translation_memory_repository.dart';
import 'package:twmt/services/translation_memory/text_normalizer.dart';
import 'package:twmt/services/translation_memory/tmx_service.dart';

import '../../../helpers/fakes/fake_logger.dart';

class _MockRepo extends Mock implements TranslationMemoryRepository {}

void main() {
  late _MockRepo repo;
  late TmxService service;
  late Directory tmpDir;

  setUp(() {
    repo = _MockRepo();
    service = TmxService(
      repository: repo,
      normalizer: TextNormalizer(),
      logger: FakeLogger(),
    );
    tmpDir = Directory.systemTemp.createTempSync('tmx_lang_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  // Helper: write a TMX document to a temp file and import it.
  Future<List<TmxEntry>> importTmx(String body) async {
    final path = p.join(tmpDir.path, 'fixture.tmx');
    File(path).writeAsStringSync(
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<tmx version="1.4">'
      '<header srclang="en" creationtool="TWMT" creationtoolversion="1.0" '
      'datatype="plaintext" segtype="sentence" adminlang="en" o-tmf="TWMT"/>'
      '<body>$body</body>'
      '</tmx>',
    );
    final result = await service.importFromTmx(filePath: path);
    expect(result.isOk, true, reason: 'import should succeed: $result');
    return result.unwrap();
  }

  test(
      'parses unit whose source tuv uses a regional variant (en-US) of '
      'header srclang (en), with a fr-FR target', () async {
    final entries = await importTmx(
      '<tu>'
      '<tuv xml:lang="en-US"><seg>Hello world</seg></tuv>'
      '<tuv xml:lang="fr-FR"><seg>Bonjour le monde</seg></tuv>'
      '</tu>',
    );

    expect(entries, hasLength(1),
        reason: 'regional-variant source must not be dropped as incomplete');
    final entry = entries.single;
    expect(entry.sourceText, 'Hello world');
    expect(entry.targetText, 'Bonjour le monde');
    expect(entry.sourceLanguage, 'en-US');
    expect(entry.targetLanguage, 'fr-FR');
  });

  test('matches base subtag case-insensitively (EN-gb source)', () async {
    final entries = await importTmx(
      '<tu>'
      '<tuv xml:lang="EN-gb"><seg>Colour</seg></tuv>'
      '<tuv xml:lang="fr"><seg>Couleur</seg></tuv>'
      '</tu>',
    );

    expect(entries, hasLength(1));
    expect(entries.single.sourceText, 'Colour');
    expect(entries.single.targetText, 'Couleur');
  });

  test(
      'with multiple target tuvs the FIRST matching target is kept '
      'deterministically', () async {
    final entries = await importTmx(
      '<tu>'
      '<tuv xml:lang="en"><seg>Yes</seg></tuv>'
      '<tuv xml:lang="fr"><seg>Oui</seg></tuv>'
      '<tuv xml:lang="de"><seg>Ja</seg></tuv>'
      '</tu>',
    );

    expect(entries, hasLength(1));
    // First non-source tuv (fr) wins; the later de tuv must not overwrite it.
    expect(entries.single.targetText, 'Oui');
    expect(entries.single.targetLanguage, 'fr');
  });

  test('still drops genuinely incomplete units (source only)', () async {
    final entries = await importTmx(
      '<tu>'
      '<tuv xml:lang="en-US"><seg>Lonely source</seg></tuv>'
      '</tu>',
    );

    expect(entries, isEmpty,
        reason: 'a unit with no target must remain an incomplete drop');
  });
}
