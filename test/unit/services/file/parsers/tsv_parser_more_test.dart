import 'dart:convert' show latin1;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/parsers/tsv_parser.dart';

/// Complementary coverage for [TsvParser].
///
/// The sibling `tsv_parser_test.dart` already exercises the happy paths
/// (header skipping, basic 2-/3-column entries, the simple invalid-line and
/// missing-file stream errors). This file targets the still-uncovered
/// surface:
///   * `parseString` escape-sequence branches (`\t`, `\\`, `\r`) and the
///     silent single-column skip / blank-line / trailing-newline branches.
///   * `parseFileStream` escape handling, boolean-flag column dropping,
///     whitespace preservation, CRLF handling, `FileParsingException` field
///     contents, non-default encoding, and the missing-file Err details.
void main() {
  group('TsvParser.parseString (escape + edge branches)', () {
    final parser = TsvParser();

    test('unescapes \\t into a literal tab inside the value', () {
      const content = 'k\tcol1\\tcol2\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, 'col1\tcol2');
    });

    test('unescapes \\r into a carriage return', () {
      const content = 'k\tline\\rmore\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, 'line\rmore');
    });

    test('unescapes a literal backslash (\\\\) without consuming following n',
        () {
      // r'\\n' must become a literal backslash followed by the letter n,
      // NOT a backslash + newline. This exercises the \x00 marker round-trip
      // in _unescapeValue.
      const content = 'path\tC:\\\\n_drive\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, r'C:\n_drive');
    });

    test('handles mixed escapes in one value', () {
      const content = 'k\ta\\tb\\nc\\\\d\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, 'a\tb\nc\\d');
    });

    test('silently skips a single-column line (no tab) without erroring', () {
      const content = 'lonely_token\n'
          'good_key\tGood value\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      // The malformed line is dropped, not surfaced as a comment or entry.
      expect(result!.entries, hasLength(1));
      expect(result.entries.single.key, 'good_key');
      expect(result.comments, isEmpty);
    });

    test('skips blank and whitespace-only lines between entries', () {
      const content = 'a\tAlpha\n'
          '\n'
          '   \n'
          'b\tBeta\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries, hasLength(2));
      expect(result.entries[0].key, 'a');
      expect(result.entries[1].key, 'b');
    });

    test('a trailing newline does not create a spurious empty entry', () {
      const content = 'only\tValue\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries, hasLength(1));
    });

    test('records line numbers (1-based) across blank lines and comments', () {
      const content = '# header comment\n' // line 1
          '\n' // line 2
          'first\tOne\n' // line 3
          'second\tTwo\n'; // line 4

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries[0].lineNumber, 3);
      expect(result.entries[1].lineNumber, 4);
    });

    test('an empty comment line yields an empty comment string', () {
      const content = '#\n'
          'k\tv\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.comments, ['']);
      expect(result.entries.single.key, 'k');
    });

    test('keeps a 4-column row joined when the last column is not a bool flag',
        () {
      // parts.length >= 3 but the last column is "extra", not true/false, so
      // every column after the key is re-joined with tabs as the value.
      const content = 'k\tone\ttwo\tthree\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, 'one\ttwo\tthree');
    });

    test('drops the trailing bool flag but keeps internal tabs in the value',
        () {
      // 4 columns where the last IS a bool flag -> columns 1..n-2 become the
      // value, preserving the interior tab.
      const content = 'k\tone\ttwo\tfalse\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, 'one\ttwo');
    });

    test('treats a row with only key and bool flag as an empty value', () {
      // parts.length == 2 -> the bool-flag branch is NOT taken (needs >= 3),
      // so "true" is the value here, proving the guard is on length.
      const content = 'k\ttrue\n';

      final result = parser.parseString(content: content, fileName: 't.tsv');

      expect(result, isNotNull);
      expect(result!.entries.single.value, 'true');
    });
  });

  group('TsvParser.parseFileStream (escape + flag + encoding branches)', () {
    final parser = TsvParser();
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('tsv_parser_more_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Future<String> writeTsv(String content, {String name = 'text_en.loc.tsv'}) async {
      final file = File('${tempDir.path}${Platform.pathSeparator}$name');
      await file.writeAsString(content);
      return file.path;
    }

    Future<List<Result<LocalizationEntry, FileParsingException>>> collect(
        String filePath,
        {String encoding = 'utf-8'}) {
      return parser
          .parseFileStream(filePath: filePath, encoding: encoding)
          .toList();
    }

    List<LocalizationEntry> okEntries(
        List<Result<LocalizationEntry, FileParsingException>> results) {
      return [
        for (final r in results)
          if (r.isOk) r.value,
      ];
    }

    test('unescapes \\t, \\r and \\\\ in streamed values', () async {
      final path = await writeTsv(
        'tab\ta\\tb\n'
        'cr\tx\\ry\n'
        'bs\tC:\\\\n_drive\n',
      );

      final entries = okEntries(await collect(path));

      expect(entries, hasLength(3));
      expect(entries[0].value, 'a\tb');
      expect(entries[1].value, 'x\ry');
      expect(entries[2].value, r'C:\n_drive');
    });

    test('drops the trailing bool flag but keeps interior tabs (stream)',
        () async {
      final path = await writeTsv('k\tone\ttwo\tfalse\n');

      final entries = okEntries(await collect(path));

      expect(entries.single.value, 'one\ttwo');
    });

    test('preserves significant leading/trailing whitespace in the value',
        () async {
      final path = await writeTsv('frag_of\t of \ttrue\n');

      final entries = okEntries(await collect(path));

      expect(entries.single.key, 'frag_of');
      expect(entries.single.value, ' of ');
    });

    test('handles CRLF line endings (LineSplitter strips the terminator)',
        () async {
      final path = await writeTsv('greeting\tHello\r\nfarewell\tBye\r\n');

      final entries = okEntries(await collect(path));

      expect(entries, hasLength(2));
      expect(entries[0].value, 'Hello');
      expect(entries[1].value, 'Bye');
    });

    test('populates FileParsingException line number and raw line on a bad row',
        () async {
      final path = await writeTsv(
        'ok\tValue\n'
        'broken_no_tab\n',
      );

      final results = await collect(path);

      expect(results, hasLength(2));
      expect(results[0].isOk, isTrue);
      expect(results[1].isErr, isTrue);
      final err = results[1].error;
      expect(err.filePath, path);
      expect(err.lineNumber, 2);
      expect(err.rawLine, 'broken_no_tab');
      expect(err.message, contains('Invalid TSV format'));
    });

    test('reads a file written in latin1 with the latin1 encoding param',
        () async {
      // 'é' (U+00E9) is a single byte 0xE9 in latin1; writing + reading with
      // latin1 exercises the non-default encoding branch of parseFileStream.
      final file =
          File('${tempDir.path}${Platform.pathSeparator}latin.loc.tsv');
      await file.writeAsString('accent\tCafé\n', encoding: latin1);

      final entries = okEntries(await collect(file.path, encoding: 'latin1'));

      expect(entries.single.value, 'Café');
    });

    test('an empty file yields no results', () async {
      final path = await writeTsv('');

      final results = await collect(path);

      expect(results, isEmpty);
    });

    test('a comments-and-blanks-only file yields no entries or errors',
        () async {
      final path = await writeTsv(
        '# just a comment\n'
        '\n'
        '   \n',
      );

      final results = await collect(path);

      expect(results, isEmpty);
    });

    test('missing file Err carries the path and line number 0', () async {
      final missing =
          '${tempDir.path}${Platform.pathSeparator}nope.loc.tsv';

      final results = await collect(missing);

      expect(results, hasLength(1));
      expect(results.single.isErr, isTrue);
      final err = results.single.error;
      expect(err.filePath, missing);
      expect(err.lineNumber, 0);
      expect(err.message, contains('not found'));
    });
  });
}
