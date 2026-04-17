import 'package:characters/characters.dart';

/// Returns up to [max] alphanumeric initials from [name], uppercased.
///
/// - Splits on whitespace, takes the first alphanumeric character of each word.
/// - When [name] has a single word, returns the first [max] alphanumeric
///   characters of that word.
/// - Strips diacritics heuristically (via unicode upper mapping; accented
///   letters become their base uppercase form for common Latin-1 cases).
/// - Returns an empty string when [name] is blank.
String initials(String name, {int max = 2}) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '';
  final words = trimmed.split(RegExp(r'\s+'));
  final buffer = StringBuffer();
  if (words.length == 1) {
    for (final ch in words.first.characters) {
      if (buffer.length >= max) break;
      final up = ch.toUpperCase();
      if (_isAlphanumeric(up)) buffer.write(up);
    }
    return buffer.toString();
  }
  for (final word in words) {
    if (buffer.length >= max) break;
    for (final ch in word.characters) {
      final up = ch.toUpperCase();
      if (_isAlphanumeric(up)) {
        buffer.write(up);
        break;
      }
    }
  }
  return buffer.toString();
}

bool _isAlphanumeric(String upperChar) {
  if (upperChar.length != 1) return true;
  final code = upperChar.codeUnitAt(0);
  final isDigit = code >= 0x30 && code <= 0x39;
  final isUpper = code >= 0x41 && code <= 0x5A;
  final isLatin1Upper = code >= 0xC0 && code <= 0xDE && code != 0xD7;
  return isDigit || isUpper || isLatin1Upper;
}
