import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/file/tsv_localization_parser.dart';

// Tests for TsvLocalizationParser, which reads RPFM-exported .loc.tsv files
// from disk. Because the parser reads from the filesystem (it uses dart:io
// directly), every case is exercised through a temp-file harness.
//
// The first group contains regression tests for data fidelity: the RPFM
// .loc.tsv `text` column (parts[1]) must be imported verbatim. Two historical
// bugs:
//  - rows whose text was literally "false" were dropped (the boolean tooltip
//    flag lives in parts[2], not the text column);
//  - leading/trailing whitespace was trimmed off the value, diverging from the
//    binary .loc parser and silently altering strings on re-export.

void main() {
  late TsvLocalizationParser parser;
  late Directory tempDir;

  setUp(() async {
    parser = TsvLocalizationParser();
    tempDir = await Directory.systemTemp.createTemp('tsv_loc_parser_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<String> writeTsv(
    String content, {
    String name = 'text_en.loc.tsv',
  }) async {
    final file = File('${tempDir.path}${Platform.pathSeparator}$name');
    await file.writeAsString(content);
    return file.path;
  }

  group('parseFile - data fidelity (regression)', () {
    test('imports an entry whose text is literally "false"', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'option_disabled\tfalse\ttrue\n'
        'unit_name\tSwordsmen\tfalse\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final entries = result.value.entries;
      final disabled = entries.where((e) => e.key == 'option_disabled');
      expect(disabled, hasLength(1),
          reason: 'A source string of "false" must not be dropped on import');
      expect(disabled.single.value, 'false');
    });

    test('preserves significant leading/trailing whitespace in the value',
        () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'frag_of\t of \ttrue\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'Expected Ok but got: $result');
      final entry =
          result.value.entries.singleWhere((e) => e.key == 'frag_of');
      expect(entry.value, ' of ',
          reason: 'Leading/trailing spaces are data and must be preserved');
    });

    test('ignores the third tooltip column entirely', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'flag_key\tReal text\tfalse\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      // The "false" in parts[2] is the tooltip flag; the value is parts[1].
      expect(result.value.entries.single.value, 'Real text');
    });
  });

  group('parseFile - happy path', () {
    test('parses a valid RPFM TSV (header + #Loc metadata + entries)',
        () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'unit_name_1\tSwordsmen\ttrue\n'
        'unit_name_2\tSpearmen\tfalse\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'Valid TSV should parse: $result');
      final file = result.value;
      expect(file.entries, hasLength(2));
      expect(file.entries[0].key, 'unit_name_1');
      expect(file.entries[0].value, 'Swordsmen');
      expect(file.entries[1].key, 'unit_name_2');
      expect(file.entries[1].value, 'Spearmen');
    });

    test('preserves entry order', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'a\tAlpha\ttrue\n'
        'b\tBravo\ttrue\n'
        'c\tCharlie\ttrue\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(
        result.value.entries.map((e) => e.key).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('sets file metadata (path, fileName without extension, encoding)',
        () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
        name: 'text_units_en.loc.tsv',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      final file = result.value;
      expect(file.filePath, path);
      // `.loc.tsv` and `.tsv` are stripped from the stored file name.
      expect(file.fileName, 'text_units_en');
      // Output encoding is always reported as UTF-8 regardless of input.
      expect(file.encoding, 'UTF-8');
      expect(file.comments, isEmpty);
    });

    test('assigns 1-indexed line numbers matching the source row', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n' // line 1
        '#Loc;1;loc_PackedFile\n' // line 2
        'first\tFirst\ttrue\n' // line 3
        'second\tSecond\ttrue\n', // line 4
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      final entries = result.value.entries;
      expect(entries[0].lineNumber, 3);
      expect(entries[1].lineNumber, 4);
    });
  });

  group('parseFile - header / metadata handling', () {
    test('two-column variant (no metadata line) skips only the header',
        () async {
      // No '#' on line 2, so startIndex stays at 1 and the first data row is
      // parsed.
      final path = await writeTsv(
        'key\ttext\n'
        'greeting_key\tHello\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries, hasLength(1));
      expect(result.value.entries.single.key, 'greeting_key');
      expect(result.value.entries.single.value, 'Hello');
    });

    test('the first line is always treated as a header and dropped', () async {
      // Even a data-shaped first line is consumed as the header row.
      final path = await writeTsv(
        'first_key\tFirst value\n'
        'second_key\tSecond value\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries, hasLength(1));
      expect(result.value.entries.single.key, 'second_key');
    });

    test('file with only a header row yields zero entries', () async {
      final path = await writeTsv('key\ttext\ttooltip\n');

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries, isEmpty);
    });

    test('file with header + metadata only yields zero entries', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries, isEmpty);
    });

    test('blank lines between entries are skipped', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k1\tV1\ttrue\n'
        '\n'
        '   \n'
        'k2\tV2\ttrue\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries.map((e) => e.key).toList(), ['k1', 'k2']);
    });
  });

  group('parseFile - malformed content guards', () {
    test('lines with fewer than two columns are skipped', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'no_tab_here\n'
        'good_key\tGood value\ttrue\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      // The single-column line is dropped; only the valid row survives.
      expect(result.value.entries, hasLength(1));
      expect(result.value.entries.single.key, 'good_key');
    });

    test('rows with an empty key are skipped', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        '\tValue with empty key\ttrue\n'
        'real_key\tReal value\ttrue\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries, hasLength(1));
      expect(result.value.entries.single.key, 'real_key');
    });

    test('rows with an empty value are skipped', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'empty_val\t\ttrue\n'
        'real_key\tReal value\ttrue\n',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.entries, hasLength(1));
      expect(result.value.entries.single.key, 'real_key');
    });
  });

  group('parseFile - empty file', () {
    test('a completely empty file returns a FileParsingException', () async {
      final path = await writeTsv('');

      final result = await parser.parseFile(filePath: path);

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileParsingException>());
    });
  });

  group('parseFile - language-code derivation', () {
    test('derives "en" from a text_en.loc.tsv filename', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
        name: 'text_en.loc.tsv',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.languageCode, 'en');
    });

    test('derives "fr" from a text_fr.loc.tsv filename', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
        name: 'text_fr.loc.tsv',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.languageCode, 'fr');
    });

    test('falls back to "en" when the filename has no language suffix',
        () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
        name: 'units.tsv',
      );

      final result = await parser.parseFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.languageCode, 'en');
    });

    test('explicit languageCode override wins over the filename', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
        name: 'text_en.loc.tsv',
      );

      final result =
          await parser.parseFile(filePath: path, languageCode: 'de');

      expect(result.isOk, isTrue);
      // Override is used verbatim even though the filename says "en".
      expect(result.value.languageCode, 'de');
    });
  });

  group('parseFile - file not found', () {
    test('returns FileNotFoundException for a missing file', () async {
      final missing =
          '${tempDir.path}${Platform.pathSeparator}does_not_exist.loc.tsv';

      final result = await parser.parseFile(filePath: missing);

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileNotFoundException>());
      expect((result.error as FileNotFoundException).filePath, missing);
    });
  });

  group('parseFile - encoding parameter', () {
    test('honors a non-default encoding argument without error', () async {
      // The parser accepts an encoding argument but always reports UTF-8 for
      // RPFM-exported TSV; passing a different value must not break parsing.
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
      );

      final result =
          await parser.parseFile(filePath: path, encoding: 'utf-16');

      expect(result.isOk, isTrue);
      expect(result.value.encoding, 'UTF-8');
    });
  });

  group('extractLanguageCode', () {
    test('extracts a two-letter code from a "_xx" suffix', () {
      expect(parser.extractLanguageCode('text_en'), 'en');
      expect(parser.extractLanguageCode('text_fr.loc'), 'fr');
    });

    test('returns null when no language suffix is present', () {
      expect(parser.extractLanguageCode('units'), isNull);
      expect(parser.extractLanguageCode('text_eng'), isNull);
    });
  });

  group('unsupported operations', () {
    test('parseString is not supported and returns an Err', () async {
      final result = await parser.parseString(
        content: 'key\ttext\n',
        fileName: 'x.tsv',
        languageCode: 'en',
      );

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileParsingException>());
    });

    test('generateFileContent is not supported and returns an Err', () async {
      const file = LocalizationFile(
        fileName: 'x',
        filePath: 'x.tsv',
        languageCode: 'en',
        entries: [],
      );

      final result = await parser.generateFileContent(file: file);

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileWriteException>());
    });

    test('writeFile is not supported and returns an Err', () async {
      const file = LocalizationFile(
        fileName: 'x',
        filePath: 'x.tsv',
        languageCode: 'en',
        entries: [],
      );

      final result =
          await parser.writeFile(file: file, destinationPath: 'out.tsv');

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileWriteException>());
    });

    test('mergeFiles is not supported and returns an Err', () async {
      final result = await parser.mergeFiles(files: const []);

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileServiceException>());
    });

    test('splitFile is not supported and returns an Err', () async {
      const file = LocalizationFile(
        fileName: 'x',
        filePath: 'x.tsv',
        languageCode: 'en',
        entries: [],
      );

      final result = await parser.splitFile(file: file);

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileServiceException>());
    });

    test('parseFileStream throws UnimplementedError', () {
      expect(
        () => parser.parseFileStream(filePath: 'x.tsv'),
        throwsUnimplementedError,
      );
    });
  });

  group('validateFile', () {
    test('returns valid for an existing .tsv file', () async {
      final path = await writeTsv(
        'key\ttext\ttooltip\n'
        '#Loc;1;loc_PackedFile\n'
        'k\tv\ttrue\n',
      );

      final result = await parser.validateFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.isValid, isTrue);
    });

    test('returns FileNotFoundException for a missing file', () async {
      final missing = '${tempDir.path}${Platform.pathSeparator}nope.tsv';

      final result = await parser.validateFile(filePath: missing);

      expect(result.isErr, isTrue);
      expect(result.error, isA<FileNotFoundException>());
    });

    test('returns invalid for an existing non-.tsv file', () async {
      final path = await writeTsv('key\ttext\n', name: 'notatsv.txt');

      final result = await parser.validateFile(filePath: path);

      expect(result.isOk, isTrue);
      expect(result.value.isValid, isFalse);
      expect(result.value.errors, isNotEmpty);
    });
  });

  group('detectEncoding', () {
    test('always reports utf-8 for RPFM TSV', () async {
      final result = await parser.detectEncoding(filePath: 'whatever.tsv');

      expect(result.isOk, isTrue);
      expect(result.value, 'utf-8');
    });
  });

  group('generatePrefixedFileName', () {
    test('builds a Total War style prefixed name', () {
      expect(
        parser.generatePrefixedFileName('units', 'fr'),
        '!!!!!!!!!!_FR_units',
      );
    });
  });
}
