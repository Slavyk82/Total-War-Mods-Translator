import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _baseLocale = 'en';

void main() {
  group('i18n format consistency', () {
    final i18nDir = Directory('lib/i18n');
    final placeholderRe = RegExp(r'\{(\w+)\}');

    test('placeholders are identical across locales for the same key', () {
      final baseDir = Directory(p.join(i18nDir.path, _baseLocale));
      expect(baseDir.existsSync(), isTrue);

      // Collect base placeholder maps: namespace filename → (key path → token set).
      final basePlaceholders = <String, Map<String, Set<String>>>{};
      for (final f in baseDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.i18n.json')) continue;
        final ns = p.basename(f.path);
        basePlaceholders[ns] =
            _placeholders(jsonDecode(f.readAsStringSync()), placeholderRe);
      }

      for (final localeDir in i18nDir.listSync().whereType<Directory>()) {
        final code = p.basename(localeDir.path);
        if (code == _baseLocale) continue;

        for (final entry in basePlaceholders.entries) {
          final ns = entry.key;
          final baseMap = entry.value;
          final localeFile = File(p.join(localeDir.path, ns));
          if (!localeFile.existsSync()) continue; // completeness test owns this
          final localeMap = _placeholders(
              jsonDecode(localeFile.readAsStringSync()), placeholderRe);

          for (final key in baseMap.keys) {
            expect(
              localeMap[key] ?? <String>{},
              equals(baseMap[key]),
              reason:
                  'Placeholders mismatch for "$key" in lib/i18n/$code/$ns',
            );
          }
        }
      }
    });
  });
}

Map<String, Set<String>> _placeholders(Object? json, RegExp re,
    [String prefix = '']) {
  final out = <String, Set<String>>{};
  if (json is Map) {
    json.forEach((k, v) {
      final path = prefix.isEmpty ? k.toString() : '$prefix.$k';
      out.addAll(_placeholders(v, re, path));
    });
  } else if (json is String) {
    out[prefix] = re.allMatches(json).map((m) => m.group(1)!).toSet();
  }
  return out;
}
