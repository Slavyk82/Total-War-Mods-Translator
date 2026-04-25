import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const String _baseLocale = 'en';

void main() {
  group('i18n keys completeness', () {
    final i18nDir = Directory('lib/i18n');

    test('every non-base locale matches the base key set per namespace', () {
      expect(i18nDir.existsSync(), isTrue,
          reason: 'lib/i18n must exist');

      final baseDir = Directory(p.join(i18nDir.path, _baseLocale));
      expect(baseDir.existsSync(), isTrue,
          reason: 'Base locale directory lib/i18n/$_baseLocale must exist');

      // Collect base namespaces: filename → flattened key set.
      final baseNamespaces = <String, Set<String>>{};
      for (final f in baseDir.listSync().whereType<File>()) {
        if (!f.path.endsWith('.i18n.json')) continue;
        final ns = p.basename(f.path);
        baseNamespaces[ns] =
            _flatten(jsonDecode(f.readAsStringSync()));
      }

      expect(baseNamespaces, isNotEmpty,
          reason: 'Base locale $_baseLocale has no .i18n.json files');

      // Every other locale dir must mirror baseNamespaces.
      for (final localeDir in i18nDir.listSync().whereType<Directory>()) {
        final code = p.basename(localeDir.path);
        if (code == _baseLocale) continue;

        for (final entry in baseNamespaces.entries) {
          final ns = entry.key;
          final baseKeys = entry.value;

          final localeFile = File(p.join(localeDir.path, ns));
          expect(localeFile.existsSync(), isTrue,
              reason: 'Missing $ns in lib/i18n/$code (present in base)');

          final localeKeys =
              _flatten(jsonDecode(localeFile.readAsStringSync()));

          expect(localeKeys.difference(baseKeys), isEmpty,
              reason:
                  'lib/i18n/$code/$ns has keys not present in base $_baseLocale');
          expect(baseKeys.difference(localeKeys), isEmpty,
              reason:
                  'lib/i18n/$code/$ns is missing keys present in base $_baseLocale');
        }
      }
    });
  });
}

Set<String> _flatten(Object? json, [String prefix = '']) {
  if (json is Map) {
    final keys = <String>{};
    json.forEach((k, v) {
      final path = prefix.isEmpty ? k.toString() : '$prefix.$k';
      keys.addAll(_flatten(v, path));
    });
    return keys;
  }
  return {prefix};
}
