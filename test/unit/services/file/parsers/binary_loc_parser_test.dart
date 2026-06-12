import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/models/localization_entry.dart';
import 'package:twmt/services/file/parsers/binary_loc_parser.dart';

/// Reverse-engineered binary RPFM .loc byte format (see
/// lib/services/file/parsers/binary_loc_parser.dart):
///
/// - Optional BOM: FF FE (UTF-16 LE marker), skipped if present.
/// - Optional LOC header: 12 bytes total. Detected when the 4 bytes at the
///   current offset, read via String.fromCharCodes, start with 'LOC'. The
///   parser then unconditionally skips 12 bytes (4 magic + 4 version +
///   4 count/offset). The version/count bytes are NEVER validated.
/// - Entries: a flat sequence of fields. Each entry is exactly 3 fields:
///   key, text, tooltip.
/// - Each field: a 2-byte LITTLE-ENDIAN length prefix giving the number of
///   UTF-16 code units, followed by that many UTF-16 LE code units (2 bytes
///   each, low byte first). length == 0 yields an empty string and consumes
///   only the 2 prefix bytes.
/// - Between entries / fields the parser will skip a SINGLE null byte only
///   when bytes[offset] == 0 && bytes[offset+1] != 0. We deliberately keep all
///   field lengths in 1..255 so the low byte of every length prefix is
///   non-zero, which means the separator-skip path is never triggered and the
///   layout is a clean concatenation of fields.
/// - The outer loop runs `while (offset < bytes.length - 3)`. After the final
///   field consumes the buffer exactly, offset == bytes.length and the loop
///   ends cleanly.
///
/// The value the parser stores per entry is chosen by _detectEntryType:
///   - "identifier" = contains '_' AND no ' ' (space).
///   - Type 1: key is an identifier and text is NOT -> (key, text).
///   - Type 2: key is NOT an identifier, text IS, tooltip is NOT ->
///     (text, tooltip).
///   - Fallback (anything else): (key, text).

/// Encodes a single UTF-16 LE length-prefixed field.
List<int> _encodeField(String s) {
  final units = s.codeUnits; // UTF-16 code units.
  if (units.length > 0xFFFF) {
    throw ArgumentError('Field too long for a 16-bit length prefix');
  }
  final out = <int>[];
  // 2-byte little-endian length prefix (count of UTF-16 code units).
  out.add(units.length & 0xFF);
  out.add((units.length >> 8) & 0xFF);
  for (final u in units) {
    out.add(u & 0xFF); // low byte first (little endian)
    out.add((u >> 8) & 0xFF);
  }
  return out;
}

/// A logical entry as it appears on the wire: three raw fields.
class _RawEntry {
  final String key;
  final String text;
  final String tooltip;
  const _RawEntry(this.key, this.text, this.tooltip);
}

/// Builds a complete .loc byte buffer.
///
/// [withBom] prepends the FF FE BOM.
/// [withHeader] prepends a 12-byte 'LOC\0' + version + count header.
Uint8List _buildLoc(
  List<_RawEntry> entries, {
  bool withBom = true,
  bool withHeader = true,
}) {
  final bytes = <int>[];
  if (withBom) {
    bytes.addAll([0xFF, 0xFE]);
  }
  if (withHeader) {
    // 'LOC' + NUL (4 bytes magic), then 4 version bytes, then 4 count bytes.
    // The parser only checks that the first 4 bytes start with 'LOC' and then
    // blindly skips 12 bytes, so the remaining 8 bytes are arbitrary.
    bytes.addAll('LOC'.codeUnits); // 'L','O','C'
    bytes.add(0x00); // NUL completing the 4-byte magic
    bytes.addAll([0x01, 0x00, 0x00, 0x00]); // version
    bytes.addAll([entries.length & 0xFF, 0x00, 0x00, 0x00]); // count (ignored)
  }
  for (final e in entries) {
    bytes.addAll(_encodeField(e.key));
    bytes.addAll(_encodeField(e.text));
    bytes.addAll(_encodeField(e.tooltip));
  }
  return Uint8List.fromList(bytes);
}

void main() {
  group('BinaryLocParser.parseFile', () {
    final parser = BinaryLocParser();

    test('is a singleton (factory returns the same instance)', () {
      expect(identical(BinaryLocParser(), BinaryLocParser()), isTrue);
    });

    test('parses a multi-entry Type 1 file (key=identifier, value=text)',
        () async {
      // Type 1: key is an identifier (has '_', no space), text is natural
      // language, tooltip is another identifier -> stores (key, text).
      final bytes = _buildLoc(const [
        _RawEntry('unit_name_1', 'Swordsmen', 'unit_subtitle_1'),
        _RawEntry('unit_name_2', 'Spearmen', 'unit_subtitle_2'),
        _RawEntry('unit_name_3', 'Archers', 'unit_subtitle_3'),
      ]);

      final result = await parser.parseFile(
        filePath: 'C:/mods/text_en.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      final entries = result.value;
      expect(entries, hasLength(3));

      expect(entries[0].key, 'unit_name_1');
      expect(entries[0].value, 'Swordsmen');
      expect(entries[1].key, 'unit_name_2');
      expect(entries[1].value, 'Spearmen');
      expect(entries[2].key, 'unit_name_3');
      expect(entries[2].value, 'Archers');

      // Order + line numbering (1-based entry index) preserved.
      expect(entries.map((e) => e.lineNumber).toList(), [1, 2, 3]);
    });

    test('parses an empty .loc (header only, zero entries) to an empty list',
        () async {
      final bytes = _buildLoc(const []);
      // BOM (2) + header (12) = 14 bytes, offset lands at 14 == length,
      // so the entry loop never runs.
      expect(bytes.length, 14);

      final result = await parser.parseFile(
        filePath: 'empty.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, isEmpty);
    });

    test('parses entries with no BOM and no LOC header', () async {
      // Without BOM/header the parser starts reading fields at offset 0.
      final bytes = _buildLoc(
        const [_RawEntry('greeting_key', 'Hello there', 'greeting_sub')],
        withBom: false,
        withHeader: false,
      );

      final result = await parser.parseFile(
        filePath: 'no_header.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, hasLength(1));
      expect(result.value.single.key, 'greeting_key');
      expect(result.value.single.value, 'Hello there');
    });

    test('rejects a file smaller than the 10-byte minimum', () async {
      final bytes = Uint8List.fromList([0xFF, 0xFE, 0x01, 0x00, 0x05]); // 5 bytes

      final result = await parser.parseFile(
        filePath: 'C:/mods/tiny.loc',
        bytes: bytes,
      );

      expect(result.isErr, isTrue);
      final err = result.error;
      expect(err, isA<FileParsingException>());
      expect(err.message, 'File too small to be a valid LOC file');
      // fileName is derived from the path's last segment.
      expect(err.filePath, 'tiny.loc');
      expect(err.lineNumber, 0);
    });

    test('zero-length min-size buffer is rejected', () async {
      final result = await parser.parseFile(
        filePath: 'zero.loc',
        bytes: const [],
      );

      expect(result.isErr, isTrue);
      expect(result.error.message, 'File too small to be a valid LOC file');
    });

    test('round-trips Unicode (accented + CJK) values via UTF-16 LE decoding',
        () async {
      // BMP characters only: each is a single UTF-16 code unit, which the
      // 2-byte length prefix counts directly.
      const accented = 'Crème brûlée'; // Latin-1 + combining-free accents.
      const cjk = '剣士の名前'; // Japanese: each char is one BMP code unit.

      final bytes = _buildLoc(const [
        _RawEntry('food_name_1', accented, 'food_sub_1'),
        _RawEntry('jp_unit_1', cjk, 'jp_sub_1'),
      ]);

      final result = await parser.parseFile(
        filePath: 'unicode.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      final entries = result.value;
      expect(entries, hasLength(2));
      expect(entries[0].value, accented);
      expect(entries[1].value, cjk);
    });

    test('preserves significant leading/trailing whitespace in values',
        () async {
      // Total War strings can carry meaningful edge spaces (e.g. " of ").
      // " of " contains a space so it is treated as natural-language text,
      // keeping the Type 1 (key, text) mapping.
      final bytes = _buildLoc(const [
        _RawEntry('frag_of', ' of ', 'frag_sub'),
      ]);

      final result = await parser.parseFile(
        filePath: 'frags.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.single.value, ' of ');
    });

    test('handles an empty (zero-length) field value', () async {
      // length == 0 yields '' and consumes only the 2 prefix bytes.
      // key 'title_1' is an identifier, text '' is not -> Type 1 (key, text='').
      final bytes = _buildLoc(const [
        _RawEntry('title_1', '', 'title_sub_1'),
      ]);

      final result = await parser.parseFile(
        filePath: 'emptyval.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, hasLength(1));
      expect(result.value.single.key, 'title_1');
      expect(result.value.single.value, '');
    });

    test('detects Type 2 entries (key=text natural language, value=tooltip)',
        () async {
      // Type 2: key is natural language (has space), text is an identifier,
      // tooltip is natural language -> stores (text, tooltip).
      final bytes = _buildLoc(const [
        _RawEntry(
          'Commanders of Ulthuan',
          'wh2_main_hef_prince_description',
          'The noble families of the High Elves',
        ),
      ]);

      final result = await parser.parseFile(
        filePath: 'desc.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      final entry = result.value.single;
      expect(entry.key, 'wh2_main_hef_prince_description');
      expect(entry.value, 'The noble families of the High Elves');
    });

    test('falls back to (key, text) when type heuristics are ambiguous',
        () async {
      // Both key and text look like identifiers -> neither Type 1 nor Type 2
      // condition holds, so the fallback (key, text) is used.
      final bytes = _buildLoc(const [
        _RawEntry('alpha_key', 'beta_key', 'gamma_key'),
      ]);

      final result = await parser.parseFile(
        filePath: 'ambiguous.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      final entry = result.value.single;
      expect(entry.key, 'alpha_key');
      expect(entry.value, 'beta_key');
    });

    test('stops cleanly at a truncated trailing entry (incomplete field)',
        () async {
      // One complete entry followed by a partial second entry: a key field
      // whose declared length exceeds the remaining bytes. _parseEntry returns
      // Err on that field, the loop breaks, and the first entry is still Ok.
      final good = _buildLoc(
        const [_RawEntry('unit_name_1', 'Swordsmen', 'unit_sub_1')],
        withBom: false,
        withHeader: false,
      );

      // Partial second entry: length prefix says 10 code units (=20 bytes)
      // but we only supply 4 bytes of payload.
      final truncated = <int>[
        ...good,
        0x0A, 0x00, // length = 10 code units
        0x41, 0x00, 0x42, 0x00, // only 2 code units of payload supplied
      ];

      final result = await parser.parseFile(
        filePath: 'truncated.loc',
        bytes: Uint8List.fromList(truncated),
      );

      // The parser breaks on the bad entry rather than failing the whole file.
      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, hasLength(1));
      expect(result.value.single.key, 'unit_name_1');
      expect(result.value.single.value, 'Swordsmen');
    });

    test('ignores trailing garbage that is too short to form an entry',
        () async {
      // The outer loop condition is `offset < bytes.length - 3`, so up to 3
      // stray trailing bytes after the last full entry are simply ignored.
      final base = _buildLoc(
        const [_RawEntry('k_one', 'Value one', 's_one')],
        withBom: false,
        withHeader: false,
      );
      final withTail = Uint8List.fromList([...base, 0x00, 0x00, 0x00]);

      final result = await parser.parseFile(
        filePath: 'tail.loc',
        bytes: withTail,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, hasLength(1));
      expect(result.value.single.key, 'k_one');
      expect(result.value.single.value, 'Value one');
    });

    test('non-LOC magic is treated as immediate field data (no header skip)',
        () async {
      // When the first 4 bytes do not start with 'LOC', the 12-byte header is
      // NOT skipped; parsing begins by reading a field length prefix at the
      // (post-BOM) offset. We craft a valid single entry without a header so
      // the very first bytes are a length prefix instead of 'LOC'.
      final bytes = _buildLoc(
        const [_RawEntry('plain_key', 'Plain value', 'plain_sub')],
        withBom: false,
        withHeader: false,
      );
      // First two bytes are the key length prefix (9, 0), not 'LO'.
      expect(bytes[0], 'plain_key'.length);
      expect(bytes[1], 0);

      final result = await parser.parseFile(
        filePath: 'plain.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value.single.key, 'plain_key');
      expect(result.value.single.value, 'Plain value');
    });

    test('produces LocalizationEntry instances of the expected type', () async {
      final bytes = _buildLoc(const [
        _RawEntry('type_check_key', 'Type check value', 'type_check_sub'),
      ]);

      final result = await parser.parseFile(
        filePath: 'types.loc',
        bytes: bytes,
      );

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, isA<List<LocalizationEntry>>());
      expect(result.value.single, isA<LocalizationEntry>());
    });
  });
}
