import 'package:flutter_test/flutter_test.dart';
import 'package:twmt/config/database_config.dart';

void main() {
  group('DatabaseConfig.getPragmaStatements', () {
    test('uses 64 MB cache_size for 6M+ row scalability', () {
      final pragmas = DatabaseConfig.getPragmaStatements();
      expect(
        pragmas.any((p) => p.contains('cache_size = -64000')),
        true,
        reason: 'cache_size should be -64000 (64 MB) for TM workloads',
      );
    });

    test('enables mmap_size of 256 MB for kernel-level page cache', () {
      final pragmas = DatabaseConfig.getPragmaStatements();
      expect(
        pragmas.any((p) => p.contains('mmap_size = 268435456')),
        true,
        reason: 'mmap_size should be 256 MB (268435456 bytes)',
      );
    });

    test('still includes WAL journal mode and foreign keys', () {
      final pragmas = DatabaseConfig.getPragmaStatements();
      expect(pragmas, contains('PRAGMA journal_mode = WAL'));
      expect(pragmas, contains('PRAGMA foreign_keys = ON'));
    });
  });
}
