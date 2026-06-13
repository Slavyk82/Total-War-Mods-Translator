import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/localization_parser_impl.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';

/// Coverage-focused tests for [LocalizationParserImpl] exercising the methods
/// the original suite does not touch: content generation, disk writing,
/// validation, encoding detection, language/filename helpers, merge and split.
///
/// These are deliberately driven through the public API with crafted in-memory
/// [LocalizationFile]/[LocalizationEntry] values and real temp files so the
/// orchestration branches (Ok paths, error/strategy branches) are covered.

LocalizationEntry _entry(String key, String value) =>
    LocalizationEntry(key: key, value: value);

LocalizationFile _file({
  String fileName = 'sample.loc',
  String filePath = '',
  String languageCode = 'en',
  String encoding = 'utf-8',
  List<LocalizationEntry> entries = const [],
  List<String> comments = const [],
}) =>
    LocalizationFile(
      fileName: fileName,
      filePath: filePath,
      languageCode: languageCode,
      encoding: encoding,
      entries: entries,
      comments: comments,
    );

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('loc_parser_cov_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  String pathIn(String name) =>
      '${tmp.path}${Platform.pathSeparator}$name';

  group('generateFileContent', () {
    test('emits comments and key/value lines (includeComments true)', () async {
      final file = _file(
        entries: [_entry('k1', 'Value one'), _entry('k2', 'Value two')],
        comments: ['Header comment', 'Second comment'],
      );

      final result =
          await LocalizationParserImpl().generateFileContent(file: file);

      expect(result.isOk, isTrue, reason: 'got: $result');
      final content = result.value;
      expect(content, contains('# Header comment'));
      expect(content, contains('# Second comment'));
      expect(content, contains('k1\tValue one'));
      expect(content, contains('k2\tValue two'));
    });

    test('omits comments when includeComments is false', () async {
      final file = _file(
        entries: [_entry('only', 'V')],
        comments: ['Should not appear'],
      );

      final result = await LocalizationParserImpl()
          .generateFileContent(file: file, includeComments: false);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, isNot(contains('Should not appear')));
      expect(result.value, contains('only\tV'));
    });

    test('escapes special characters (newline -> \\n) in values', () async {
      final file = _file(entries: [_entry('multi', 'line1\nline2')]);

      final result =
          await LocalizationParserImpl().generateFileContent(file: file);

      expect(result.isOk, isTrue, reason: 'got: $result');
      // The literal newline in the value is escaped back to the 2-char "\n".
      expect(result.value, contains(r'line1\nline2'));
      expect(result.value, isNot(contains('line1\nline2')));
    });

    test('empty file produces empty content (Ok)', () async {
      final result =
          await LocalizationParserImpl().generateFileContent(file: _file());

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, isEmpty);
    });
  });

  group('writeFile', () {
    test('writes generated content to disk and returns the path', () async {
      final file = _file(
        entries: [_entry('w_key', 'Written value')],
        comments: ['A comment'],
      );
      final dest = pathIn('out.tsv');

      final result = await LocalizationParserImpl()
          .writeFile(file: file, destinationPath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, dest);

      final written = await File(dest).readAsString();
      expect(written, contains('# A comment'));
      expect(written, contains('w_key\tWritten value'));
    });

    test('round-trips through parseFile after writing', () async {
      final file = _file(
        entries: [_entry('rt_a', 'Alpha'), _entry('rt_b', 'Beta')],
      );
      final dest = pathIn('roundtrip.tsv');

      final writeResult = await LocalizationParserImpl()
          .writeFile(file: file, destinationPath: dest);
      expect(writeResult.isOk, isTrue, reason: 'got: $writeResult');

      final parsed =
          await LocalizationParserImpl().parseFile(filePath: writeResult.value);
      expect(parsed.isOk, isTrue, reason: 'got: $parsed');
      expect(parsed.value.entries, hasLength(2));
      expect(parsed.value.entries[0].key, 'rt_a');
      expect(parsed.value.entries[1].value, 'Beta');
    });

    test('writing with an explicit utf-16le encoding succeeds', () async {
      final file = _file(entries: [_entry('enc_key', 'Encodé')]);
      final dest = pathIn('utf16.tsv');

      final result = await LocalizationParserImpl().writeFile(
        file: file,
        destinationPath: dest,
        encoding: 'utf-16le',
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(await File(dest).exists(), isTrue);
    });

    test('writing to a path under a non-existent directory returns an Err',
        () async {
      final file = _file(entries: [_entry('k', 'v')]);
      final badDest = pathIn(
        'no_such_dir${Platform.pathSeparator}nested${Platform.pathSeparator}out.tsv',
      );

      final result = await LocalizationParserImpl()
          .writeFile(file: file, destinationPath: badDest);

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error, isA<FileServiceException>());
    });

    test('writing to an existing directory path returns a FileSystem Err',
        () async {
      // The temp dir itself exists as a directory; writing a file to that path
      // raises a FileSystemException -> FileAccessDeniedException branch.
      final file = _file(entries: [_entry('k', 'v')]);

      final result = await LocalizationParserImpl()
          .writeFile(file: file, destinationPath: tmp.path);

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error, isA<FileServiceException>());
    });
  });

  group('validateFile', () {
    test('returns Err(FileNotFoundException) for a missing file', () async {
      final result = await LocalizationParserImpl()
          .validateFile(filePath: pathIn('missing.tsv'));

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error, isA<FileNotFoundException>());
    });

    test('valid TSV file validates as Ok with isValid true', () async {
      final dest = pathIn('valid.tsv');
      await File(dest).writeAsString('good_key\tGood value\n'
          'another\tAnother value\n');

      final result =
          await LocalizationParserImpl().validateFile(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.isValid, isTrue);
      expect(result.value.errors, isEmpty);
    });

    test('malformed TSV (no tab) yields validation errors but Ok result',
        () async {
      final dest = pathIn('bad.tsv');
      await File(dest).writeAsString('line_without_tab\n'
          'real_key\tReal value\n');

      final result =
          await LocalizationParserImpl().validateFile(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.isValid, isFalse);
      expect(result.value.errors, isNotEmpty);
    });

    test('duplicate keys surface as warnings', () async {
      final dest = pathIn('dups.tsv');
      await File(dest).writeAsString('dup\tFirst\n'
          'dup\tSecond\n');

      final result =
          await LocalizationParserImpl().validateFile(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.warnings, isNotEmpty);
    });
  });

  group('detectEncoding', () {
    test('detects UTF-8 BOM', () async {
      final dest = pathIn('utf8bom.tsv');
      await File(dest).writeAsBytes([0xEF, 0xBB, 0xBF, 0x6B, 0x09, 0x76]);

      final result =
          await LocalizationParserImpl().detectEncoding(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-8');
    });

    test('detects UTF-16 LE BOM', () async {
      final dest = pathIn('utf16le.bin');
      await File(dest).writeAsBytes([0xFF, 0xFE, 0x6B, 0x00]);

      final result =
          await LocalizationParserImpl().detectEncoding(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-16le');
    });

    test('detects UTF-16 BE BOM', () async {
      final dest = pathIn('utf16be.bin');
      await File(dest).writeAsBytes([0xFE, 0xFF, 0x00, 0x6B]);

      final result =
          await LocalizationParserImpl().detectEncoding(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-16be');
    });

    test('defaults to utf-8 when no BOM present', () async {
      final dest = pathIn('nobom.tsv');
      await File(dest).writeAsBytes([0x6B, 0x09, 0x76, 0x0A]);

      final result =
          await LocalizationParserImpl().detectEncoding(filePath: dest);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-8');
    });

    test('returns Err for a missing file', () async {
      final result = await LocalizationParserImpl()
          .detectEncoding(filePath: pathIn('nope.tsv'));

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error, isA<FileEncodingException>());
    });
  });

  group('extractLanguageCode', () {
    test('extracts and lowercases a TW-prefixed language code', () {
      expect(
        LocalizationParserImpl()
            .extractLanguageCode('!!!!!!!!!!_FR_units.loc'),
        'fr',
      );
    });

    test('returns null when filename has no prefix/lang pattern', () {
      expect(
        LocalizationParserImpl().extractLanguageCode('plain_units.loc'),
        isNull,
      );
    });

    test('returns null for an empty filename', () {
      expect(LocalizationParserImpl().extractLanguageCode(''), isNull);
    });
  });

  group('generatePrefixedFileName', () {
    test('builds the Total War prefixed filename with uppercased lang', () {
      expect(
        LocalizationParserImpl().generatePrefixedFileName('units.loc', 'fr'),
        '!!!!!!!!!!_FR_units.loc',
      );
    });

    test('uppercases an already-uppercase language code unchanged', () {
      expect(
        LocalizationParserImpl().generatePrefixedFileName('text.loc', 'DE'),
        '!!!!!!!!!!_DE_text.loc',
      );
    });
  });

  group('mergeFiles', () {
    test('returns Err for an empty list', () async {
      final result =
          await LocalizationParserImpl().mergeFiles(files: const []);

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error.message, contains('empty'));
    });

    test('returns the single file unchanged when only one is supplied',
        () async {
      final only = _file(entries: [_entry('k', 'v')]);

      final result = await LocalizationParserImpl().mergeFiles(files: [only]);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, same(only));
    });

    test('merges entries and concatenates comments from all files', () async {
      final a = _file(
        fileName: 'a.loc',
        entries: [_entry('a_key', 'A')],
        comments: ['comment a'],
      );
      final b = _file(
        fileName: 'b.loc',
        entries: [_entry('b_key', 'B')],
        comments: ['comment b'],
      );

      final result =
          await LocalizationParserImpl().mergeFiles(files: [a, b]);

      expect(result.isOk, isTrue, reason: 'got: $result');
      final merged = result.value;
      expect(merged.fileName, 'a.loc'); // metadata from first file
      expect(merged.entries, hasLength(2));
      expect(merged.keys, containsAll(<String>['a_key', 'b_key']));
      expect(merged.comments, containsAll(<String>['comment a', 'comment b']));
    });

    test('conflict "last" keeps the later value (default)', () async {
      final a = _file(entries: [_entry('dup', 'old')]);
      final b = _file(entries: [_entry('dup', 'new')]);

      final result =
          await LocalizationParserImpl().mergeFiles(files: [a, b]);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries.single.value, 'new');
    });

    test('conflict "first" keeps the earlier value', () async {
      final a = _file(entries: [_entry('dup', 'old')]);
      final b = _file(entries: [_entry('dup', 'new')]);

      final result = await LocalizationParserImpl()
          .mergeFiles(files: [a, b], conflictResolution: 'first');

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries.single.value, 'old');
    });

    test('conflict "error" returns Err on a duplicate key', () async {
      final a = _file(entries: [_entry('dup', 'old')]);
      final b = _file(entries: [_entry('dup', 'new')]);

      final result = await LocalizationParserImpl()
          .mergeFiles(files: [a, b], conflictResolution: 'error');

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error.message, contains('Duplicate key'));
    });

    test('an unknown conflict strategy returns Err', () async {
      final a = _file(entries: [_entry('dup', 'old')]);
      final b = _file(entries: [_entry('dup', 'new')]);

      final result = await LocalizationParserImpl()
          .mergeFiles(files: [a, b], conflictResolution: 'bogus');

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error.message, contains('Invalid conflict resolution'));
    });
  });

  group('splitFile', () {
    test('returns Err when maxEntriesPerFile <= 0', () async {
      final file = _file(entries: [_entry('k', 'v')]);

      final result = await LocalizationParserImpl()
          .splitFile(file: file, maxEntriesPerFile: 0);

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error.message, contains('greater than 0'));
    });

    test('returns the file as-is when it already fits', () async {
      final file = _file(entries: [_entry('k', 'v')]);

      final result = await LocalizationParserImpl()
          .splitFile(file: file, maxEntriesPerFile: 100);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, hasLength(1));
      expect(result.value.single, same(file));
    });

    test('splits into chunks with part-numbered filenames', () async {
      final entries = [
        for (var i = 0; i < 5; i++) _entry('k$i', 'v$i'),
      ];
      final file = _file(
        fileName: 'big.loc',
        entries: entries,
        comments: ['c1', 'c2', 'c3'],
      );

      final result = await LocalizationParserImpl()
          .splitFile(file: file, maxEntriesPerFile: 2);

      expect(result.isOk, isTrue, reason: 'got: $result');
      final chunks = result.value;
      expect(chunks, hasLength(3)); // ceil(5/2)
      expect(chunks[0].fileName, 'big_part1.loc');
      expect(chunks[1].fileName, 'big_part2.loc');
      expect(chunks[2].fileName, 'big_part3.loc');
      // Entry counts: 2, 2, 1
      expect(chunks[0].entries, hasLength(2));
      expect(chunks[2].entries, hasLength(1));
      // All original entries preserved across chunks.
      final allKeys =
          chunks.expand((c) => c.entries.map((e) => e.key)).toList();
      expect(allKeys, ['k0', 'k1', 'k2', 'k3', 'k4']);
    });

    test('splitting a file with no comments yields empty chunk comments',
        () async {
      final entries = [
        for (var i = 0; i < 3; i++) _entry('k$i', 'v$i'),
      ];
      final file = _file(fileName: 'noc.loc', entries: entries);

      final result = await LocalizationParserImpl()
          .splitFile(file: file, maxEntriesPerFile: 2);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, hasLength(2));
      for (final chunk in result.value) {
        expect(chunk.comments, isEmpty);
      }
    });
  });

  group('parseFile — binary parser error propagation', () {
    test('UTF-16 BOM but a too-small body returns Err from the binary parser',
        () async {
      // FF FE makes _isBinaryLocFormat true, but a body under 10 bytes makes
      // BinaryLocParser reject it; the impl propagates that Err (line 72).
      final dest = pathIn('tiny_binary.loc');
      await File(dest).writeAsBytes([0xFF, 0xFE, 0x4C, 0x4F, 0x43, 0x00]);

      final result = await LocalizationParserImpl().parseFile(filePath: dest);

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error, isA<FileParsingException>());
    });
  });

  group('parseString — error wrapping', () {
    test('valid content parses to Ok', () async {
      final result = await LocalizationParserImpl().parseString(
        content: 'k\tv\n',
        fileName: 'm.tsv',
        languageCode: 'en',
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries.single.key, 'k');
    });
  });
}
