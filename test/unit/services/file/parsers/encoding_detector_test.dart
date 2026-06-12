import 'dart:convert' show Encoding, utf8, latin1, ascii;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';
import 'package:twmt/services/file/parsers/encoding_detector.dart';

void main() {
  final detector = EncodingDetector();

  group('EncodingDetector singleton', () {
    test('factory returns the same instance', () {
      expect(identical(EncodingDetector(), EncodingDetector()), isTrue);
    });
  });

  group('EncodingDetector.detectEncoding (BOM detection via temp files)', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('enc_test_');
    });

    tearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });

    Future<String> writeBytes(List<int> bytes) async {
      final f = File('${tmp.path}${Platform.pathSeparator}sample.loc');
      await f.writeAsBytes(bytes);
      return f.path;
    }

    test('UTF-8 BOM (EF BB BF) -> "utf-8"', () async {
      // BOM followed by some ASCII content.
      final path = await writeBytes([0xEF, 0xBB, 0xBF, 0x68, 0x69]);

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-8');
    });

    test('UTF-16 LE BOM (FF FE) -> "utf-16le"', () async {
      final path = await writeBytes([0xFF, 0xFE, 0x68, 0x00]);

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-16le');
    });

    test('UTF-16 BE BOM (FE FF) -> "utf-16be"', () async {
      final path = await writeBytes([0xFE, 0xFF, 0x00, 0x68]);

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-16be');
    });

    test('no BOM but valid UTF-8 content defaults to "utf-8"', () async {
      // Plain ASCII/UTF-8 with no BOM. The detector defaults to utf-8.
      final path = await writeBytes(utf8.encode('hello world'));

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-8');
    });

    test('no BOM with UTF-16-LE-looking bytes still defaults to "utf-8"', () async {
      // "AB" encoded as UTF-16 LE bytes (0x41 0x00 0x42 0x00) but with NO BOM.
      // The detector only keys off the BOM, so it falls through to the default.
      final path = await writeBytes([0x41, 0x00, 0x42, 0x00]);

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-8',
          reason: 'Heuristic is BOM-only; no BOM => default utf-8');
    });

    test('empty file (no bytes) returns Err via the catch block', () async {
      // Reading an empty file leaves no bytes to inspect; the detector throws
      // internally ("No element") and the catch wraps it in a FileEncodingException.
      final path = await writeBytes(<int>[]);

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isErr, isTrue, reason: 'got: $result');
      expect(result.error.message, contains('Failed to detect encoding'));
    });

    test('single 0xFF byte (incomplete BOM) defaults to "utf-8"', () async {
      // Only one byte present: cannot match the 2-byte UTF-16 BOM check.
      final path = await writeBytes([0xFF]);

      final result = await detector.detectEncoding(filePath: path);

      expect(result.isOk, isTrue, reason: 'got: $result');
      expect(result.value, 'utf-8');
    });

    test('missing file -> Err(FileEncodingException) with "unknown" detected',
        () async {
      final missing =
          '${tmp.path}${Platform.pathSeparator}does_not_exist.loc';

      final result = await detector.detectEncoding(filePath: missing);

      expect(result.isErr, isTrue, reason: 'got: $result');
      final err = result.error;
      expect(err, isA<FileEncodingException>());
      expect(err.message, 'File not found for encoding detection');
      expect(err.filePath, missing);
      expect(err.detectedEncoding, 'unknown');
    });
  });

  group('EncodingDetector.getEncoding (pure name -> Encoding mapping)', () {
    test('"utf-8" and "utf8" map to dart:convert utf8', () {
      expect(detector.getEncoding('utf-8'), same(utf8));
      expect(detector.getEncoding('utf8'), same(utf8));
    });

    test('name matching is case-insensitive', () {
      expect(detector.getEncoding('UTF-8'), same(utf8));
      expect(detector.getEncoding('Latin1'), same(latin1));
    });

    test('"latin1" and "iso-8859-1" map to dart:convert latin1', () {
      expect(detector.getEncoding('latin1'), same(latin1));
      expect(detector.getEncoding('iso-8859-1'), same(latin1));
    });

    test('"ascii" maps to dart:convert ascii', () {
      expect(detector.getEncoding('ascii'), same(ascii));
    });

    test('"utf-16le" returns a custom Encoding named "utf-16le"', () {
      final enc = detector.getEncoding('utf-16le');
      expect(enc, isA<Encoding>());
      expect(enc.name, 'utf-16le');
    });

    test('"utf-16be" returns a custom Encoding named "utf-16be"', () {
      final enc = detector.getEncoding('utf-16be');
      expect(enc, isA<Encoding>());
      expect(enc.name, 'utf-16be');
    });

    test('"utf-16" and "utf16" default to the LE codec', () {
      expect(detector.getEncoding('utf-16').name, 'utf-16le');
      expect(detector.getEncoding('utf16').name, 'utf-16le');
    });

    test('unknown name falls back to utf8', () {
      expect(detector.getEncoding('shift-jis'), same(utf8));
      expect(detector.getEncoding(''), same(utf8));
    });
  });

  group('UTF-16 LE codec round-trip', () {
    // ASCII + accented (Latin-1 Supplement) + BMP CJK characters.
    const sample = 'Hello, éàü — 日本語 中文';

    test('encode then decode round-trips equal', () {
      final enc = detector.getEncoding('utf-16le');
      final bytes = enc.encode(sample);
      final decoded = enc.decode(bytes);
      expect(decoded, sample);
    });

    test('produces 2 bytes per UTF-16 code unit (little-endian order)', () {
      final enc = detector.getEncoding('utf-16le');
      final bytes = enc.encode(sample);
      expect(bytes.length, sample.codeUnits.length * 2);
      // First char 'H' (0x0048) in little-endian => [0x48, 0x00].
      expect(bytes[0], 0x48);
      expect(bytes[1], 0x00);
    });

    test('decoder ignores a trailing odd byte (loop stops one short)', () {
      // 'Hi' (0x48 0x00 0x69 0x00) plus a dangling 0x00 byte.
      final enc = detector.getEncoding('utf-16le');
      final decoded = enc.decode([0x48, 0x00, 0x69, 0x00, 0x00]);
      expect(decoded, 'Hi');
    });
  });

  group('UTF-16 BE codec round-trip', () {
    const sample = 'Hello, éàü — 日本語 中文';

    test('encode then decode round-trips equal', () {
      final enc = detector.getEncoding('utf-16be');
      final bytes = enc.encode(sample);
      final decoded = enc.decode(bytes);
      expect(decoded, sample);
    });

    test('produces 2 bytes per code unit (big-endian order)', () {
      final enc = detector.getEncoding('utf-16be');
      final bytes = enc.encode(sample);
      expect(bytes.length, sample.codeUnits.length * 2);
      // First char 'H' (0x0048) in big-endian => [0x00, 0x48].
      expect(bytes[0], 0x00);
      expect(bytes[1], 0x48);
    });

    test('LE and BE encodings of the same string have swapped byte pairs', () {
      final le = detector.getEncoding('utf-16le').encode('Hi');
      final be = detector.getEncoding('utf-16be').encode('Hi');
      expect(le.length, be.length);
      // Each 2-byte pair is reversed between LE and BE.
      for (var i = 0; i < le.length; i += 2) {
        expect(le[i], be[i + 1]);
        expect(le[i + 1], be[i]);
      }
    });
  });
}
