import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/models/localization_file.dart';
import 'package:twmt/services/file/localization_parser_impl.dart';

/// Tests for [LocalizationParserImpl] — the orchestrator that decides whether
/// a localization file is a binary RPFM .loc or a text TSV, reads it from disk,
/// dispatches to the matching specialized parser, and wraps the result in a
/// [LocalizationFile].
///
/// Dispatch rule (see `_isBinaryLocFormat`): a byte buffer is treated as a
/// binary .loc ONLY when it is >= 4 bytes AND either
///   - starts with the UTF-16 LE BOM `FF FE`, or
///   - its first three bytes spell ASCII `LOC`.
/// Everything else (including a `.loc` extension carrying TSV text, a UTF-8
/// BOM, or anything shorter than 4 bytes) is routed to the TSV parser via
/// `utf8.decode(..., allowMalformed: true)`. Dispatch is by magic bytes, NOT
/// by file extension.

/// Encodes a single UTF-16 LE length-prefixed field for the binary .loc body.
/// Mirrors the encoder in binary_loc_parser_test.dart: a 2-byte little-endian
/// count of UTF-16 code units followed by those code units, low byte first.
List<int> _encodeField(String s) {
  final units = s.codeUnits;
  final out = <int>[];
  out.add(units.length & 0xFF);
  out.add((units.length >> 8) & 0xFF);
  for (final u in units) {
    out.add(u & 0xFF);
    out.add((u >> 8) & 0xFF);
  }
  return out;
}

/// A logical .loc entry on the wire: three raw fields (key, text, tooltip).
class _RawEntry {
  final String key;
  final String text;
  final String tooltip;
  const _RawEntry(this.key, this.text, this.tooltip);
}

/// Builds a binary .loc buffer with a leading FF FE BOM and a 12-byte
/// 'LOC\0' + version + count header (so `_isBinaryLocFormat` returns true via
/// the BOM check, and `BinaryLocParser` skips the header).
Uint8List _buildLoc(List<_RawEntry> entries) {
  final bytes = <int>[];
  bytes.addAll([0xFF, 0xFE]); // UTF-16 LE BOM
  bytes.addAll('LOC'.codeUnits); // magic 'L','O','C'
  bytes.add(0x00); // NUL completing the 4-byte magic
  bytes.addAll([0x01, 0x00, 0x00, 0x00]); // version (ignored)
  bytes.addAll([entries.length & 0xFF, 0x00, 0x00, 0x00]); // count (ignored)
  for (final e in entries) {
    bytes.addAll(_encodeField(e.key));
    bytes.addAll(_encodeField(e.text));
    bytes.addAll(_encodeField(e.tooltip));
  }
  return Uint8List.fromList(bytes);
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('loc_parser_');
  });

  tearDown(() async {
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Future<String> write(String name, List<int> bytes) async {
    final f = File('${tmp.path}${Platform.pathSeparator}$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  group('LocalizationParserImpl singleton', () {
    test('factory returns the same instance', () {
      expect(
        identical(LocalizationParserImpl(), LocalizationParserImpl()),
        isTrue,
      );
    });
  });

  group('parseFile — TSV dispatch (text content)', () {
    test('parses a 3-column RPFM .tsv into entries (Ok)', () async {
      const content = 'key\ttext\ttooltip\n'
          '#Loc;1;loc_PackedFile\n'
          'unit_name_1\tSwordsmen\ttrue\n'
          'unit_name_2\tSpearmen\tfalse\n';
      final path = await write('text_en.loc.tsv', utf8.encode(content));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      final file = result.value;
      // Header row + #Loc metadata comment are not entries.
      expect(file.entries, hasLength(2));
      expect(file.entries[0].key, 'unit_name_1');
      expect(file.entries[0].value, 'Swordsmen');
      expect(file.entries[1].key, 'unit_name_2');
      expect(file.entries[1].value, 'Spearmen');
    });

    test('a .loc file whose bytes are TSV text dispatches to the TSV parser '
        '(extension does not force binary)', () async {
      // Magic-byte dispatch: although the extension is .loc, the content is
      // plain TSV with no BOM and no LOC header, so it must go to TSV.
      const content = 'greeting_key\tHello there\n'
          'farewell_key\tGoodbye\n';
      final path = await write('plain_text.loc', utf8.encode(content));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries, hasLength(2));
      expect(result.value.entries[0].key, 'greeting_key');
      expect(result.value.entries[0].value, 'Hello there');
      expect(result.value.entries[1].key, 'farewell_key');
    });

    test('a short (<4 byte) buffer cannot be binary and goes to TSV', () async {
      // Below the 4-byte minimum `_isBinaryLocFormat` short-circuits to false,
      // so even bytes that would otherwise look like a header go to TSV.
      const content = 'k\tv\n'; // 4 bytes once encoded, but no tab-less issues
      final path = await write('tiny.tsv', utf8.encode(content));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries.single.key, 'k');
      expect(result.value.entries.single.value, 'v');
    });

    test('empty file routes to TSV path and yields an empty entry list (Ok)',
        () async {
      // Zero bytes -> length < 4 -> not binary -> TSV parseString of '' which
      // returns an empty (entries, comments) record, never null.
      final path = await write('empty.tsv', const <int>[]);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries, isEmpty);
    });

    test('TWMT-format TSV preserves comments-as-skipped and key/value entries',
        () async {
      const content = '# Generated by TWMT\n'
          '\n'
          'my_key\tMy value\n'
          'other_key\tValue with \\n newline\n';
      final path = await write('export.tsv', utf8.encode(content));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries, hasLength(2));
      expect(result.value.entries[0].key, 'my_key');
      expect(result.value.entries[1].value, 'Value with \n newline');
    });
  });

  group('parseFile — binary .loc dispatch (magic bytes)', () {
    test('parses a multi-entry binary .loc (BOM + LOC header) into entries',
        () async {
      final bytes = _buildLoc(const [
        _RawEntry('unit_name_1', 'Swordsmen', 'unit_sub_1'),
        _RawEntry('unit_name_2', 'Spearmen', 'unit_sub_2'),
      ]);
      final path = await write('text_en.loc', bytes);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      final entries = result.value.entries;
      expect(entries, hasLength(2));
      expect(entries[0].key, 'unit_name_1');
      expect(entries[0].value, 'Swordsmen');
      expect(entries[1].key, 'unit_name_2');
      expect(entries[1].value, 'Spearmen');
    });

    test('binary path round-trips Unicode values via UTF-16 LE', () async {
      const accented = 'Crème brûlée';
      const cjk = '剣士の名前';
      final bytes = _buildLoc(const [
        _RawEntry('food_name_1', accented, 'food_sub_1'),
        _RawEntry('jp_unit_1', cjk, 'jp_sub_1'),
      ]);
      final path = await write('unicode.loc', bytes);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries[0].value, accented);
      expect(result.value.entries[1].value, cjk);
    });

    test('a buffer whose first 3 bytes spell LOC (no BOM) is treated as binary',
        () async {
      // Force the header-magic branch of `_isBinaryLocFormat` (no FF FE BOM).
      final body = <int>[];
      body.addAll('LOC'.codeUnits);
      body.add(0x00); // 4-byte magic
      body.addAll([0x01, 0x00, 0x00, 0x00]); // version
      body.addAll([0x01, 0x00, 0x00, 0x00]); // count
      body.addAll(_encodeField('hdr_key'));
      body.addAll(_encodeField('Header dispatched'));
      body.addAll(_encodeField('hdr_sub'));
      final path = await write('magic.loc', body);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries.single.key, 'hdr_key');
      expect(result.value.entries.single.value, 'Header dispatched');
    });

    test('binary .loc with header only (zero entries) yields empty entry list',
        () async {
      final bytes = _buildLoc(const []);
      final path = await write('headeronly.loc', bytes);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries, isEmpty);
    });
  });

  group('parseFile — encoding detection / BOM handling', () {
    test('UTF-8 BOM is NOT binary; routes to TSV (BOM stripped from key)',
        () async {
      // EF BB BF is a UTF-8 BOM, which `_isBinaryLocFormat` does not match, so
      // the file is decoded as UTF-8 and parsed as TSV. The TSV parser strips
      // the leading BOM, so the first key is clean.
      final body = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('alpha_key\tAlpha\n')];
      final path = await write('utf8bom.tsv', body);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries, hasLength(1));
      expect(result.value.entries.single.key, 'alpha_key');
      expect(result.value.entries.single.value, 'Alpha');
    });

    test('UTF-16 LE BOM triggers the binary parser, not TSV', () async {
      // A file that starts FF FE is dispatched to the binary parser regardless
      // of intent; we supply a well-formed binary body so it parses cleanly.
      final bytes = _buildLoc(const [
        _RawEntry('bom_key', 'Bom value', 'bom_sub'),
      ]);
      final path = await write('utf16bom.loc', bytes);

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.entries.single.key, 'bom_key');
      expect(result.value.entries.single.value, 'Bom value');
    });

    test('encoding passed in is stored verbatim on the returned file',
        () async {
      final path = await write('enc.tsv', utf8.encode('k1\tv1\n'));

      final result = await LocalizationParserImpl()
          .parseFile(filePath: path, encoding: 'utf-16');

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.encoding, 'utf-16');
    });

    test('encoding defaults to utf-8 when not supplied', () async {
      final path = await write('encdefault.tsv', utf8.encode('k1\tv1\n'));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.encoding, 'utf-8');
    });
  });

  group('parseFile — language code / filename metadata', () {
    test('extracts language code from a Total War prefixed filename', () async {
      // extractLanguageCode pattern: !+_([A-Z]{2})_ -> lowercased.
      final path =
          await write('!!!!!!!!!!_FR_units.loc.tsv', utf8.encode('k\tv\n'));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.languageCode, 'fr');
      expect(result.value.fileName, '!!!!!!!!!!_FR_units.loc.tsv');
    });

    test('explicit languageCode overrides filename-derived code', () async {
      final path =
          await write('!!!!!!!!!!_FR_units.loc.tsv', utf8.encode('k\tv\n'));

      final result = await LocalizationParserImpl()
          .parseFile(filePath: path, languageCode: 'de');

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.languageCode, 'de');
    });

    test('falls back to "en" when no language code is in the filename',
        () async {
      final path = await write('plain_name.tsv', utf8.encode('k\tv\n'));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.languageCode, 'en');
    });

    test('fileName and filePath on the result reflect the source path',
        () async {
      final path = await write('meta_check.tsv', utf8.encode('k\tv\n'));

      final result = await LocalizationParserImpl().parseFile(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.fileName, 'meta_check.tsv');
      expect(result.value.filePath, path);
      expect(result.value.comments, isEmpty);
    });
  });

  group('parseFile — error handling', () {
    test('missing file returns Err(FileNotFoundException)', () async {
      final missing = '${tmp.path}${Platform.pathSeparator}does_not_exist.tsv';

      final result =
          await LocalizationParserImpl().parseFile(filePath: missing);

      expect(result.isErr, isTrue);
      final err = result.error;
      expect(err, isA<FileNotFoundException>());
      expect((err as FileNotFoundException).filePath, missing);
      expect(err.message, contains('not found'));
    });
  });

  group('parseString (TSV in-memory)', () {
    test('parses TSV content into an Ok(LocalizationFile)', () async {
      final result = await LocalizationParserImpl().parseString(
        content: 'my_key\tMy value\nother\tSecond\n',
        fileName: 'mem.tsv',
        languageCode: 'fr',
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      final file = result.value;
      expect(file.fileName, 'mem.tsv');
      expect(file.languageCode, 'fr');
      expect(file.filePath, ''); // set later when writing to disk
      expect(file.encoding, 'utf-8');
      expect(file.entries, hasLength(2));
      expect(file.entries[0].key, 'my_key');
      expect(file.entries[0].value, 'My value');
    });

    test('preserves leading comment lines as comments', () async {
      final result = await LocalizationParserImpl().parseString(
        content: '# A header comment\nkv_key\tValue\n',
        fileName: 'c.tsv',
        languageCode: 'en',
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.comments, ['A header comment']);
      expect(result.value.entries.single.key, 'kv_key');
    });
  });

  group('parseFileStream (delegates to TSV streaming parser)', () {
    Future<List<LocalizationEntry>> okEntries(String path) async {
      final results =
          await LocalizationParserImpl().parseFileStream(filePath: path).toList();
      return [
        for (final r in results)
          if (r.isOk) r.value,
      ];
    }

    test('streams entries from a TSV file', () async {
      const content = 'key\ttext\ttooltip\n'
          '#Loc;1;loc_PackedFile\n'
          'stream_1\tFirst\ttrue\n'
          'stream_2\tSecond\tfalse\n';
      final path = await write('stream.loc.tsv', utf8.encode(content));

      final entries = await okEntries(path);

      expect(entries, hasLength(2));
      expect(entries[0].key, 'stream_1');
      expect(entries[0].value, 'First');
      expect(entries[1].key, 'stream_2');
      expect(entries[1].value, 'Second');
    });

    test('yields Err for a malformed line but keeps streaming', () async {
      const content = 'no_tab_line\n'
          'good_key\tGood value\n';
      final path = await write('streamerr.tsv', utf8.encode(content));

      final results =
          await LocalizationParserImpl().parseFileStream(filePath: path).toList();

      expect(results, hasLength(2));
      expect(results[0].isErr, isTrue);
      expect(results[1].isOk, isTrue);
      expect(results[1].value.key, 'good_key');
    });

    test('yields a single Err for a missing file', () async {
      final missing = '${tmp.path}${Platform.pathSeparator}nope_stream.tsv';

      final results = await LocalizationParserImpl()
          .parseFileStream(filePath: missing)
          .toList();

      expect(results, hasLength(1));
      expect(results.single.isErr, isTrue);
      expect(results.single.error, isA<FileParsingException>());
    });
  });
}
