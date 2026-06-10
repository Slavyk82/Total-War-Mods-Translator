import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/config/database_config.dart';
import 'package:twmt/models/common/service_exception.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migration_service.dart';

import '../../helpers/fakes/fake_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseConfig.databaseVersion freeze', () {
    test('databaseVersion is frozen at 1 — do NOT bump it', () {
      expect(
        DatabaseConfig.databaseVersion,
        1,
        reason:
            'DatabaseConfig.databaseVersion is FROZEN at 1 by design. '
            'MigrationService.runMigrations has NO incremental upgrade path: '
            'it only handles user_version 0 (fresh install) or '
            'user_version == databaseVersion (up to date). Bumping this value '
            'would make every existing installation throw on startup and '
            'instruct users to DELETE their database, destroying all their '
            'projects, translations, and translation memory. '
            'Schema evolution must instead go through the idempotent '
            'MigrationRegistry '
            '(lib/services/database/migrations/migration_registry.dart), '
            'which runs at every startup via '
            'MigrationService.ensurePerformanceIndexes(). '
            'See the doc comment on databaseVersion in '
            'lib/config/database_config.dart before touching this.',
      );
    });
  });

  group('MigrationService.runMigrations version mismatch', () {
    late Database db;

    setUp(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      MigrationService.loggerForTesting = FakeLogger();

      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      DatabaseService.setTestDatabase(db);
    });

    tearDown(() async {
      await db.close();
      DatabaseService.resetTestDatabase();
    });

    test(
        'throws a helpful error mentioning the version mismatch when '
        'user_version is higher than the app version', () async {
      // Simulate a database written by a (hypothetical) future app version.
      await db.execute('PRAGMA user_version = 99');

      await expectLater(
        MigrationService.runMigrations(),
        throwsA(
          isA<TWMTDatabaseException>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('99'),
              contains('${DatabaseConfig.databaseVersion}'),
              contains('higher than app version'),
            ),
          ),
        ),
        reason: 'a version mismatch must surface a descriptive error, '
            'not silently corrupt or reinitialize the database',
      );
    });
  });
}
