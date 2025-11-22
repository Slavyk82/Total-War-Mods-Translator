import 'dart:convert' show Encoding, utf8, latin1, ascii, Converter;
import 'dart:io';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Encoding detection and conversion utilities for localization files
///
/// Handles:
/// - BOM (Byte Order Mark) detection
/// - UTF-8, UTF-16 LE/BE encoding detection
/// - Encoding conversion to Dart Encoding objects
class EncodingDetector {
  /// Singleton instance
  static final EncodingDetector _instance = EncodingDetector._internal();

  factory EncodingDetector() => _instance;

  EncodingDetector._internal();

  /// Detect encoding from file by examining BOM
  Future<Result<String, FileEncodingException>> detectEncoding({
    required String filePath,
  }) async {
    try {
      final file = File(filePath);

      if (!await file.exists()) {
        return Err(
          FileEncodingException(
            'File not found for encoding detection',
            filePath,
            detectedEncoding: 'unknown',
          ),
        );
      }

      // Read first few bytes for BOM detection
      final bytes = await file.openRead(0, 4).first;

      // Check for BOM (Byte Order Mark)
      if (bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF) {
        return Ok('utf-8');
      }

      if (bytes.length >= 2) {
        if (bytes[0] == 0xFF && bytes[1] == 0xFE) {
          return Ok('utf-16le');
        }
        if (bytes[0] == 0xFE && bytes[1] == 0xFF) {
          return Ok('utf-16be');
        }
      }

      // Default to UTF-8
      return Ok('utf-8');
    } catch (e, stackTrace) {
      return Err(
        FileEncodingException(
          'Failed to detect encoding: ${e.toString()}',
          filePath,
          detectedEncoding: 'unknown',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Convert encoding string to Dart Encoding
  Encoding getEncoding(String encodingName) {
    switch (encodingName.toLowerCase()) {
      case 'utf-8':
      case 'utf8':
        return utf8;
      case 'utf-16le':
        return _Utf16LeCodec();
      case 'utf-16be':
        return _Utf16BeCodec();
      case 'utf-16':
      case 'utf16':
        return _Utf16LeCodec(); // Default to LE
      case 'latin1':
      case 'iso-8859-1':
        return latin1;
      case 'ascii':
        return ascii;
      default:
        return utf8;
    }
  }
}

/// UTF-16 Little Endian codec
class _Utf16LeCodec extends Encoding {
  @override
  Converter<List<int>, String> get decoder => const _Utf16LeDecoder();

  @override
  Converter<String, List<int>> get encoder => const _Utf16LeEncoder();

  @override
  String get name => 'utf-16le';
}

/// UTF-16 Big Endian codec
class _Utf16BeCodec extends Encoding {
  @override
  Converter<List<int>, String> get decoder => const _Utf16BeDecoder();

  @override
  Converter<String, List<int>> get encoder => const _Utf16BeEncoder();

  @override
  String get name => 'utf-16be';
}

/// UTF-16 LE Decoder
class _Utf16LeDecoder extends Converter<List<int>, String> {
  const _Utf16LeDecoder();

  @override
  String convert(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
}

/// UTF-16 BE Decoder
class _Utf16BeDecoder extends Converter<List<int>, String> {
  const _Utf16BeDecoder();

  @override
  String convert(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
}

/// UTF-16 LE Encoder
class _Utf16LeEncoder extends Converter<String, List<int>> {
  const _Utf16LeEncoder();

  @override
  List<int> convert(String input) {
    final bytes = <int>[];
    for (final unit in input.codeUnits) {
      bytes.add(unit & 0xFF);
      bytes.add((unit >> 8) & 0xFF);
    }
    return bytes;
  }
}

/// UTF-16 BE Encoder
class _Utf16BeEncoder extends Converter<String, List<int>> {
  const _Utf16BeEncoder();

  @override
  List<int> convert(String input) {
    final bytes = <int>[];
    for (final unit in input.codeUnits) {
      bytes.add((unit >> 8) & 0xFF);
      bytes.add(unit & 0xFF);
    }
    return bytes;
  }
}
