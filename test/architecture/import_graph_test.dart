import 'package:flutter_test/flutter_test.dart';
import 'import_graph.dart' as ig;

void main() {
  group('resolveImport', () {
    test('keeps a package:twmt import as a lib/ path', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/features/mods/widgets/foo.dart',
        rawImport: 'package:twmt/services/shared/i_logging_service.dart',
      );
      expect(r, 'lib/services/shared/i_logging_service.dart');
    });

    test('resolves a relative import against the importing file dir', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/features/mods/widgets/foo.dart',
        rawImport: '../../../services/shared/i_logging_service.dart',
      );
      expect(r, 'lib/services/shared/i_logging_service.dart');
    });

    test('returns null for non-twmt package imports', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/features/mods/widgets/foo.dart',
        rawImport: 'package:flutter/material.dart',
      );
      expect(r, isNull);
    });

    test('returns null for dart: imports', () {
      final r = ig.resolveImport(
        importingLibPath: 'lib/a/b.dart',
        rawImport: 'dart:io',
      );
      expect(r, isNull);
    });
  });
}
