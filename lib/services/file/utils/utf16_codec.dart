import 'dart:convert' show Encoding, Converter;

/// UTF-16 Little Endian codec for Windows file encoding support
///
/// Used by FileServiceImpl to read/write files with UTF-16LE encoding,
/// which is commonly used in Windows applications.
class Utf16LeCodec extends Encoding {
  /// Singleton instance
  static const Utf16LeCodec instance = Utf16LeCodec._();

  const Utf16LeCodec._();

  /// Factory constructor returning singleton
  factory Utf16LeCodec() => instance;

  @override
  Converter<List<int>, String> get decoder => const Utf16LeDecoder();

  @override
  Converter<String, List<int>> get encoder => const Utf16LeEncoder();

  @override
  String get name => 'utf-16le';
}

/// UTF-16 Big Endian codec for file encoding support
///
/// Used by FileServiceImpl to read/write files with UTF-16BE encoding.
class Utf16BeCodec extends Encoding {
  /// Singleton instance
  static const Utf16BeCodec instance = Utf16BeCodec._();

  const Utf16BeCodec._();

  /// Factory constructor returning singleton
  factory Utf16BeCodec() => instance;

  @override
  Converter<List<int>, String> get decoder => const Utf16BeDecoder();

  @override
  Converter<String, List<int>> get encoder => const Utf16BeEncoder();

  @override
  String get name => 'utf-16be';
}

/// Decoder for UTF-16 Little Endian encoded bytes to String
///
/// Converts byte pairs in little endian order (LSB first) to Unicode
/// code units.
class Utf16LeDecoder extends Converter<List<int>, String> {
  const Utf16LeDecoder();

  @override
  String convert(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
}

/// Decoder for UTF-16 Big Endian encoded bytes to String
///
/// Converts byte pairs in big endian order (MSB first) to Unicode
/// code units.
class Utf16BeDecoder extends Converter<List<int>, String> {
  const Utf16BeDecoder();

  @override
  String convert(List<int> bytes) {
    final units = <int>[];
    for (var i = 0; i < bytes.length - 1; i += 2) {
      units.add((bytes[i] << 8) | bytes[i + 1]);
    }
    return String.fromCharCodes(units);
  }
}

/// Encoder for String to UTF-16 Little Endian bytes
///
/// Converts Unicode code units to byte pairs in little endian order
/// (LSB first).
class Utf16LeEncoder extends Converter<String, List<int>> {
  const Utf16LeEncoder();

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

/// Encoder for String to UTF-16 Big Endian bytes
///
/// Converts Unicode code units to byte pairs in big endian order
/// (MSB first).
class Utf16BeEncoder extends Converter<String, List<int>> {
  const Utf16BeEncoder();

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
