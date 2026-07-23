import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/config/database_config.dart';
import 'package:twmt/services/backup/database_backup_service.dart';
import 'package:twmt/services/database/database_service.dart';
import 'package:twmt/services/database/migration_service.dart';

import '../../helpers/test_bootstrap.dart';

/// Tests for [DatabaseBackupService] against a real on-disk SQLite database
/// in WAL mode (finding M29: live-file copy produced torn/stale backups;
/// the service now snapshots via VACUUM INTO and writes the archive
/// atomically via temp-file + rename).
void main() {
  late Directory tempRoot;
  Database? db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await TestBootstrap.registerFakes();
    tempRoot = await Directory.systemTemp.createTemp('twmt_backup_test_');
  });

  tearDown(() async {
    if (db != null && db!.isOpen) {
      await db!.close();
    }
    db = null;
    DatabaseService.resetTestDatabase();
    try {
      await tempRoot.delete(recursive: true);
    } catch (_) {
      // Windows can briefly hold file locks; leftover temp dirs are benign.
    }
  });

  /// Open a WAL-mode database at [dbPath], create a small table and insert
  /// [rowCount] rows tagged with [tag]. Registers it as the test database.
  Future<Database> openWalDatabase(
    String dbPath, {
    int rowCount = 50,
    String tag = 'seed',
  }) async {
    final database = await databaseFactory.openDatabase(dbPath);
    await database.rawQuery('PRAGMA journal_mode=WAL');
    await database
        .execute('CREATE TABLE IF NOT EXISTS items (id INTEGER PRIMARY KEY, v TEXT)');
    // A real TWMT database always carries user_version >= 1 after its first
    // initialization; checkpoint so the version is persisted into the main
    // file header (backup validation reads it from there) while the row data
    // inserted below still lives in the WAL.
    await database
        .execute('PRAGMA user_version = ${DatabaseConfig.databaseVersion}');
    await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    for (var i = 0; i < rowCount; i++) {
      await database.insert('items', {'v': '$tag-$i'});
    }
    DatabaseService.setTestDatabase(database);
    return database;
  }

  /// Extract every file from the zip at [zipPath] into [targetDir].
  Future<Set<String>> extractZip(String zipPath, Directory targetDir) async {
    final archive =
        ZipDecoder().decodeBytes(await File(zipPath).readAsBytes());
    final names = <String>{};
    for (final file in archive) {
      if (file.isFile) {
        await File(p.join(targetDir.path, file.name))
            .writeAsBytes(file.content as List<int>);
        names.add(file.name);
      }
    }
    return names;
  }

  /// Build a standalone (non-WAL) SQLite database file, optionally stamping
  /// [userVersion] into its header, and return its raw bytes. Used to craft
  /// backup archives by hand.
  Future<List<int>> buildDatabaseBytes({int? userVersion, int rowCount = 3}) async {
    final genDir = await Directory.systemTemp.createTemp('twmt_dbgen_');
    try {
      final dbPath = p.join(genDir.path, 'gen.db');
      final database = await databaseFactory.openDatabase(dbPath);
      await database
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      for (var i = 0; i < rowCount; i++) {
        await database.insert('items', {'v': 'crafted-$i'});
      }
      if (userVersion != null) {
        await database.execute('PRAGMA user_version = $userVersion');
      }
      await database.close();
      return await File(dbPath).readAsBytes();
    } finally {
      try {
        await genDir.delete(recursive: true);
      } catch (_) {
        // Windows can briefly hold file locks; leftover temp dirs are benign.
      }
    }
  }

  /// Write a ZIP archive at [zipPath] containing exactly [entries]
  /// (entry name -> raw bytes) and return its path.
  Future<String> writeBackupZip(
    String zipPath,
    Map<String, List<int>> entries,
  ) async {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
    }
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive)!);
    return zipPath;
  }

  /// Open the database at [dbPath] and assert integrity plus row contents.
  Future<List<String>> readBackOk(String dbPath) async {
    final restored = await databaseFactory.openDatabase(dbPath);
    try {
      final integrity = await restored.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');
      final rows = await restored.query('items', orderBy: 'id');
      return rows.map((r) => r['v'] as String).toList();
    } finally {
      await restored.close();
    }
  }

  group('createBackup', () {
    test('snapshot includes uncheckpointed WAL data and passes integrity_check',
        () async {
      final dbPath = p.join(tempRoot.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(dbPath, rowCount: 100);

      // Precondition: data still lives in the WAL, not the main file.
      final walFile = File('$dbPath-wal');
      expect(await walFile.exists(), isTrue);
      expect(await walFile.length(), greaterThan(0));

      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
      );
      final zipPath = p.join(tempRoot.path, 'out', 'backup.zip');
      final result = await service.createBackup(zipPath);
      expect(result.isOk, isTrue, reason: result.toString());

      final restoreDir =
          await Directory(p.join(tempRoot.path, 'restored')).create();
      final names = await extractZip(zipPath, restoreDir);

      // VACUUM INTO produces a self-contained main file: no WAL/SHM entries.
      expect(names, {DatabaseConfig.databaseName});

      final values =
          await readBackOk(p.join(restoreDir.path, DatabaseConfig.databaseName));
      expect(values.length, 100);
      expect(values.first, 'seed-0');
      expect(values.last, 'seed-99');
    });

    test('backup taken while writes are queued is internally consistent',
        () async {
      final dbPath = p.join(tempRoot.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(dbPath, rowCount: 10);

      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
      );
      final zipPath = p.join(tempRoot.path, 'backup.zip');

      // Queue writes without awaiting so they interleave with the backup on
      // the connection's statement queue.
      final pendingWrites = <Future<Object?>>[];
      for (var i = 0; i < 50; i++) {
        pendingWrites.add(db!.insert('items', {'v': 'concurrent-$i'}));
      }
      final result = await service.createBackup(zipPath);
      await Future.wait(pendingWrites);
      expect(result.isOk, isTrue, reason: result.toString());

      final restoreDir =
          await Directory(p.join(tempRoot.path, 'restored')).create();
      await extractZip(zipPath, restoreDir);
      final values =
          await readBackOk(p.join(restoreDir.path, DatabaseConfig.databaseName));
      // The snapshot must contain at least the pre-existing rows and only
      // fully committed concurrent rows (no torn state).
      expect(values.length, inInclusiveRange(10, 60));
      expect(values.take(10), everyElement(startsWith('seed-')));
    });

    test('success leaves no temporary .tmp file next to the archive',
        () async {
      final dbPath = p.join(tempRoot.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(dbPath, rowCount: 5);

      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
      );
      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final result = await service.createBackup(zipPath);

      expect(result.isOk, isTrue, reason: result.toString());
      expect(await File(zipPath).exists(), isTrue);
      expect(await File('$zipPath.tmp').exists(), isFalse);
    });

    test('failed write leaves neither destination nor half-written archive',
        () async {
      final dbPath = p.join(tempRoot.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(dbPath, rowCount: 5);

      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
      );
      final zipPath = p.join(tempRoot.path, 'backup.zip');
      // Block the temp path with a directory so writeAsBytes fails.
      await Directory('$zipPath.tmp').create(recursive: true);

      final result = await service.createBackup(zipPath);

      expect(result.isErr, isTrue);
      expect(await File(zipPath).exists(), isFalse,
          reason: 'a failed backup must never leave a file at the final name');
    });

    test('returns Err when the database file does not exist', () async {
      final service = DatabaseBackupService(
        databasePathProvider: () async =>
            p.join(tempRoot.path, 'missing', DatabaseConfig.databaseName),
      );
      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final result = await service.createBackup(zipPath);

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('Database file not found'));
      expect(await File(zipPath).exists(), isFalse);
      expect(await File('$zipPath.tmp').exists(), isFalse);
    });

    test(
        'legacy checkpoint-and-copy fallback produces a restorable backup set',
        () async {
      final dbPath = p.join(tempRoot.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(dbPath, rowCount: 25);

      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
        debugForceLegacySnapshot: true,
      );
      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final result = await service.createBackup(zipPath);
      expect(result.isOk, isTrue, reason: result.toString());

      final restoreDir =
          await Directory(p.join(tempRoot.path, 'restored')).create();
      final names = await extractZip(zipPath, restoreDir);
      expect(names, contains(DatabaseConfig.databaseName));

      final values =
          await readBackOk(p.join(restoreDir.path, DatabaseConfig.databaseName));
      expect(values.length, 25);
    });
  });

  group('restoreBackup', () {
    test(
        'restores snapshot data and removes stale WAL/SHM from the previous '
        'database generation', () async {
      // 1. Build a source database and back it up.
      final sourceDir =
          await Directory(p.join(tempRoot.path, 'source')).create();
      final sourceDbPath = p.join(sourceDir.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(sourceDbPath, rowCount: 7, tag: 'from_backup');

      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final backupService = DatabaseBackupService(
        databasePathProvider: () async => sourceDbPath,
      );
      expect((await backupService.createBackup(zipPath)).isOk, isTrue);
      await db!.close();
      db = null;
      DatabaseService.resetTestDatabase();

      // 2. Build a different "current" database and plant a stale WAL next
      //    to it (simulating an unclean close from the previous generation).
      final currentDir =
          await Directory(p.join(tempRoot.path, 'current')).create();
      final currentDbPath =
          p.join(currentDir.path, DatabaseConfig.databaseName);
      var currentDb = await databaseFactory.openDatabase(currentDbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      await currentDb.insert('items', {'v': 'current-data'});
      final staleWalPath = '$currentDbPath-wal';
      final staleShmPath = '$currentDbPath-shm';

      var walExistedAtReinit = true;
      var shmExistedAtReinit = true;
      Database? reopened;
      final restoreService = DatabaseBackupService(
        databasePathProvider: () async => currentDbPath,
        databaseCloser: () async {
          await currentDb.close();
          // Plant stale sidecars after close (SQLite removes the real ones
          // on a clean close).
          await File(staleWalPath).writeAsBytes(List.filled(64, 0xAB));
          await File(staleShmPath).writeAsBytes(List.filled(64, 0xCD));
        },
        databaseReinitializer: () async {
          walExistedAtReinit = await File(staleWalPath).exists();
          shmExistedAtReinit = await File(staleShmPath).exists();
          reopened = await databaseFactory.openDatabase(currentDbPath);
          DatabaseService.setTestDatabase(reopened!);
        },
      );

      final result = await restoreService.restoreBackup(zipPath);
      expect(result.isOk, isTrue, reason: result.toString());

      // Stale sidecars must be gone before the database is reopened.
      expect(walExistedAtReinit, isFalse,
          reason: 'stale -wal must be deleted before reinitialization');
      expect(shmExistedAtReinit, isFalse,
          reason: 'stale -shm must be deleted before reinitialization');

      // Restored content comes from the backup, not the old database.
      final rows = await reopened!.query('items', orderBy: 'id');
      final values = rows.map((r) => r['v'] as String).toList();
      expect(values.length, 7);
      expect(values, everyElement(startsWith('from_backup-')));
      final integrity = await reopened!.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');

      // Safety .bak files are cleaned up after a successful restore.
      expect(await File('$currentDbPath.bak').exists(), isFalse);
      expect(await File('$currentDbPath-wal.bak').exists(), isFalse);

      await reopened!.close();
      DatabaseService.resetTestDatabase();
    });

    test(
        'rollback after a failed restore removes archive sidecars that did '
        'not exist before the restore', () async {
      // 1. Build a legacy-format archive that carries -wal/-shm entries:
      //    an uncheckpointed WAL database copied file-by-file (the database
      //    is deliberately not registered with DatabaseService so the
      //    legacy path skips the checkpoint and copies live WAL/SHM files).
      final sourceDir =
          await Directory(p.join(tempRoot.path, 'source')).create();
      final sourceDbPath = p.join(sourceDir.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(sourceDbPath, rowCount: 9, tag: 'from_backup');
      DatabaseService.resetTestDatabase();

      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final backupService = DatabaseBackupService(
        databasePathProvider: () async => sourceDbPath,
        debugForceLegacySnapshot: true,
      );
      expect((await backupService.createBackup(zipPath)).isOk, isTrue);
      await db!.close();
      db = null;

      // Precondition: the archive really carries the sidecar files.
      final info = (await backupService.validateBackup(zipPath)).unwrap();
      expect(info.hasWalFile, isTrue,
          reason: 'scenario requires a -wal entry in the archive');
      expect(info.hasShmFile, isTrue,
          reason: 'scenario requires a -shm entry in the archive');

      // 2. Build the "current" database and close it cleanly so NO -wal/-shm
      //    exist before the restore (and therefore no .bak copies of them).
      final currentDir =
          await Directory(p.join(tempRoot.path, 'current')).create();
      final currentDbPath =
          p.join(currentDir.path, DatabaseConfig.databaseName);
      final currentDb = await databaseFactory.openDatabase(currentDbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      await currentDb.insert('items', {'v': 'original-row'});

      // 3. Fail the restore AFTER extraction: the first reinitialization
      //    throws, forcing the rollback path; the second (post-rollback)
      //    succeeds so the service can report a plain restore failure.
      var reinitCalls = 0;
      Database? reopened;
      final restoreService = DatabaseBackupService(
        databasePathProvider: () async => currentDbPath,
        databaseCloser: () async => currentDb.close(),
        databaseReinitializer: () async {
          reinitCalls++;
          if (reinitCalls == 1) {
            throw StateError('injected reinitialization failure');
          }
          reopened = await databaseFactory.openDatabase(currentDbPath);
          DatabaseService.setTestDatabase(reopened!);
        },
      );

      final result = await restoreService.restoreBackup(zipPath);
      expect(result.isErr, isTrue);
      expect(result.unwrapErr().requiresRestart, isFalse);
      expect(reinitCalls, 2);

      // The rolled-back state must be exactly the pre-restore file set: the
      // sidecars extracted from the archive had no .bak (they did not exist
      // before the restore) and must not survive paired with the original db.
      expect(await File('$currentDbPath-wal').exists(), isFalse,
          reason: 'rollback must delete the -wal extracted from the archive');
      expect(await File('$currentDbPath-shm').exists(), isFalse,
          reason: 'rollback must delete the -shm extracted from the archive');

      // Safety .bak files are consumed by the rollback.
      expect(await File('$currentDbPath.bak').exists(), isFalse);
      expect(await File('$currentDbPath-wal.bak').exists(), isFalse);
      expect(await File('$currentDbPath-shm.bak').exists(), isFalse);

      // The original database is back, intact, with its original rows.
      final integrity = await reopened!.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');
      final rows = await reopened!.query('items', orderBy: 'id');
      expect(rows.map((r) => r['v']).toList(), ['original-row']);

      await reopened!.close();
      DatabaseService.resetTestDatabase();
    });
  });

  group('archive entry hardening (zip-slip)', () {
    test('validateBackup rejects an archive containing a path-traversal entry',
        () async {
      final dbBytes = await buildDatabaseBytes(
        userVersion: DatabaseConfig.databaseVersion,
      );
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'evil.zip'), {
        DatabaseConfig.databaseName: dbBytes,
        '../evil.txt': [0x65, 0x76, 0x69, 0x6C],
      });

      final service = DatabaseBackupService(
        databasePathProvider: () async =>
            p.join(tempRoot.path, 'dbdir', DatabaseConfig.databaseName),
      );
      final result = await service.validateBackup(zipPath);

      expect(result.isErr, isTrue,
          reason: 'an archive with a traversal entry must fail validation');
      expect(result.unwrapErr().message, contains('unexpected archive entry'));
    });

    test('validateBackup rejects an archive containing an absolute path entry',
        () async {
      final dbBytes = await buildDatabaseBytes(
        userVersion: DatabaseConfig.databaseVersion,
      );
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'evil.zip'), {
        DatabaseConfig.databaseName: dbBytes,
        'C:/evil/evil.txt': [0x65, 0x76, 0x69, 0x6C],
      });

      final service = DatabaseBackupService(
        databasePathProvider: () async =>
            p.join(tempRoot.path, 'dbdir', DatabaseConfig.databaseName),
      );
      final result = await service.validateBackup(zipPath);

      expect(result.isErr, isTrue,
          reason: 'an archive with an absolute path entry must fail validation');
      expect(result.unwrapErr().message, contains('unexpected archive entry'));
    });

    test(
        'restoreBackup refuses a path-traversal archive and never writes '
        'outside the database directory', () async {
      final dbDir = await Directory(p.join(tempRoot.path, 'dbdir')).create();
      final dbPath = p.join(dbDir.path, DatabaseConfig.databaseName);
      final originalBytes = await buildDatabaseBytes(
        userVersion: DatabaseConfig.databaseVersion,
      );
      await File(dbPath).writeAsBytes(originalBytes);

      final backupDbBytes = await buildDatabaseBytes(
        userVersion: DatabaseConfig.databaseVersion,
        rowCount: 5,
      );
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'evil.zip'), {
        DatabaseConfig.databaseName: backupDbBytes,
        '../evil.txt': [0x65, 0x76, 0x69, 0x6C],
      });

      var closeCalls = 0;
      var reinitCalls = 0;
      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
        databaseCloser: () async => closeCalls++,
        databaseReinitializer: () async => reinitCalls++,
      );
      final result = await service.restoreBackup(zipPath);

      expect(result.isErr, isTrue);
      expect(await File(p.join(tempRoot.path, 'evil.txt')).exists(), isFalse,
          reason: 'restore must never write outside the database directory');
      expect(closeCalls, 0,
          reason: 'the archive must be rejected before the database is touched');
      expect(reinitCalls, 0);
      expect(await File(dbPath).readAsBytes(), originalBytes,
          reason: 'the current database must remain untouched');
    });
  });

  group('backup database schema-version validation', () {
    test('validateBackup rejects a database with user_version 0', () async {
      // A schema-less / uninitialized database: MigrationService would treat
      // it as fresh and silently re-run schema.sql over it after restore.
      final dbBytes = await buildDatabaseBytes(userVersion: null);
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'v0.zip'), {
        DatabaseConfig.databaseName: dbBytes,
      });

      final service = DatabaseBackupService(
        databasePathProvider: () async =>
            p.join(tempRoot.path, 'dbdir', DatabaseConfig.databaseName),
      );
      final result = await service.validateBackup(zipPath);

      expect(result.isErr, isTrue,
          reason: 'a backup with user_version 0 must fail validation');
      expect(result.unwrapErr().message, contains('no schema version'));
    });

    test(
        'validateBackup rejects a database with a newer schema version than '
        'the app supports', () async {
      final dbBytes = await buildDatabaseBytes(
        userVersion: DatabaseConfig.databaseVersion + 1,
      );
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'vN.zip'), {
        DatabaseConfig.databaseName: dbBytes,
      });

      final service = DatabaseBackupService(
        databasePathProvider: () async =>
            p.join(tempRoot.path, 'dbdir', DatabaseConfig.databaseName),
      );
      final result = await service.validateBackup(zipPath);

      expect(result.isErr, isTrue,
          reason: 'a backup with a newer schema version must fail validation');
      expect(result.unwrapErr().message, contains('newer'));
    });

    test('validateBackup rejects a twmt.db entry that is not SQLite', () async {
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'junk.zip'), {
        DatabaseConfig.databaseName: List<int>.filled(4096, 0x41),
      });

      final service = DatabaseBackupService(
        databasePathProvider: () async =>
            p.join(tempRoot.path, 'dbdir', DatabaseConfig.databaseName),
      );
      final result = await service.validateBackup(zipPath);

      expect(result.isErr, isTrue,
          reason: 'a non-SQLite database entry must fail validation');
      expect(result.unwrapErr().message, contains('not a valid SQLite'));
    });

    test(
        'restoreBackup fails on a user_version 0 database and leaves the '
        'current database intact', () async {
      final dbDir = await Directory(p.join(tempRoot.path, 'dbdir')).create();
      final dbPath = p.join(dbDir.path, DatabaseConfig.databaseName);
      final currentDb = await databaseFactory.openDatabase(dbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      await currentDb.insert('items', {'v': 'original-row'});
      await currentDb
          .execute('PRAGMA user_version = ${DatabaseConfig.databaseVersion}');
      await currentDb.close();

      final freshDbBytes = await buildDatabaseBytes(userVersion: null);
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'v0.zip'), {
        DatabaseConfig.databaseName: freshDbBytes,
      });

      var closeCalls = 0;
      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
        databaseCloser: () async => closeCalls++,
        databaseReinitializer: () async {},
      );
      final result = await service.restoreBackup(zipPath);

      expect(result.isErr, isTrue,
          reason: 'restoring an uninitialized database must fail');
      expect(closeCalls, 0,
          reason: 'the archive must be rejected before the database is touched');

      // The original database must be fully intact.
      final reopened = await databaseFactory.openDatabase(dbPath);
      try {
        final rows = await reopened.query('items', orderBy: 'id');
        expect(rows.map((r) => r['v']).toList(), ['original-row']);
      } finally {
        await reopened.close();
      }
    });
  });

  group('streaming backup and restore', () {
    test(
        'multi-megabyte database roundtrips through backup + restore with '
        'full row integrity', () async {
      // Seed well past the 1 MB stream-buffer size used by the archive
      // package so the backup/restore path has to handle multiple buffer
      // chunks per entry (the service must never materialize the database
      // in memory; this test pins the functional contract at that scale).
      final sourceDir =
          await Directory(p.join(tempRoot.path, 'source')).create();
      final sourceDbPath = p.join(sourceDir.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(sourceDbPath, rowCount: 0);
      const rowCount = 5000;
      final payload = 'x' * 1024; // ~5 MB of row data in total
      final batch = db!.batch();
      for (var i = 0; i < rowCount; i++) {
        batch.insert('items', {'v': 'big-$i-$payload'});
      }
      await batch.commit(noResult: true);

      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final backupService = DatabaseBackupService(
        databasePathProvider: () async => sourceDbPath,
      );
      final backupResult = await backupService.createBackup(zipPath);
      expect(backupResult.isOk, isTrue, reason: backupResult.toString());
      expect(await File(zipPath).length(), greaterThan(0));
      await db!.close();
      db = null;
      DatabaseService.resetTestDatabase();

      // Restore over a different current database.
      final currentDir =
          await Directory(p.join(tempRoot.path, 'current')).create();
      final currentDbPath =
          p.join(currentDir.path, DatabaseConfig.databaseName);
      final currentDb = await databaseFactory.openDatabase(currentDbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      await currentDb.insert('items', {'v': 'current-data'});

      Database? reopened;
      final restoreService = DatabaseBackupService(
        databasePathProvider: () async => currentDbPath,
        databaseCloser: () async => currentDb.close(),
        databaseReinitializer: () async {
          reopened = await databaseFactory.openDatabase(currentDbPath);
          DatabaseService.setTestDatabase(reopened!);
        },
      );
      final restoreResult = await restoreService.restoreBackup(zipPath);
      expect(restoreResult.isOk, isTrue, reason: restoreResult.toString());

      final integrity = await reopened!.rawQuery('PRAGMA integrity_check');
      expect(integrity.first.values.first, 'ok');
      final countRows =
          await reopened!.rawQuery('SELECT COUNT(*) AS c FROM items');
      expect(countRows.first['c'], rowCount,
          reason: 'every seeded row must survive');
      final first = await reopened!.query('items', orderBy: 'id', limit: 1);
      expect(first.single['v'], 'big-0-$payload');
      final last = await reopened!
          .query('items', orderBy: 'id DESC', limit: 1);
      expect(last.single['v'], 'big-${rowCount - 1}-$payload');

      await reopened!.close();
      DatabaseService.resetTestDatabase();
    });

    test(
        'backup + validate + restore leave no open file handles: the '
        'working directory can be deleted afterwards', () async {
      // Windows keeps a file locked while any handle is open: a leaked
      // Input/OutputFileStream would make this recursive delete throw.
      final workDir =
          await Directory(p.join(tempRoot.path, 'handles')).create();

      final sourceDir =
          await Directory(p.join(workDir.path, 'source')).create();
      final sourceDbPath = p.join(sourceDir.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(sourceDbPath, rowCount: 30);

      final zipPath = p.join(workDir.path, 'backup.zip');
      final backupService = DatabaseBackupService(
        databasePathProvider: () async => sourceDbPath,
      );
      expect((await backupService.createBackup(zipPath)).isOk, isTrue);
      await db!.close();
      db = null;
      DatabaseService.resetTestDatabase();

      // Validate (opens the archive) and restore (opens it again).
      expect((await backupService.validateBackup(zipPath)).isOk, isTrue);

      final currentDir =
          await Directory(p.join(workDir.path, 'current')).create();
      final currentDbPath =
          p.join(currentDir.path, DatabaseConfig.databaseName);
      final currentDb = await databaseFactory.openDatabase(currentDbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');

      Database? reopened;
      final restoreService = DatabaseBackupService(
        databasePathProvider: () async => currentDbPath,
        databaseCloser: () async => currentDb.close(),
        databaseReinitializer: () async {
          reopened = await databaseFactory.openDatabase(currentDbPath);
          DatabaseService.setTestDatabase(reopened!);
        },
      );
      expect((await restoreService.restoreBackup(zipPath)).isOk, isTrue);
      await reopened!.close();
      DatabaseService.resetTestDatabase();

      // The delete must SUCCEED: a failure here means a stream handle on
      // the zip or on one of the database files outlived the operation.
      await workDir.delete(recursive: true);
      expect(await workDir.exists(), isFalse,
          reason: 'no file handle may outlive backup/validate/restore');
    });
  });

  group('restore reinitialization brings the schema up to date', () {
    /// Apply lib/database/schema.sql (the frozen v1 baseline) verbatim,
    /// WITHOUT running any MigrationRegistry migration — the on-disk shape of
    /// a database captured by a backup taken under an old build.
    Future<void> applySchemaOnly(Database database) async {
      final schema = await File('lib/database/schema.sql').readAsString();
      for (final raw in MigrationService.splitSqlScriptForTesting(schema)) {
        final statement = raw.trim();
        if (statement.isEmpty) continue;
        await database.execute(statement);
      }
    }

    Future<bool> tableExists(Database d, String name) async {
      final rows = await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name = ?",
        [name],
      );
      return rows.isNotEmpty;
    }

    Future<bool> columnExists(Database d, String table, String column) async {
      final rows = await d.rawQuery('PRAGMA table_info($table)');
      return rows.any((r) => r['name'] == column);
    }

    test(
        'the production default reinitializer applies the incremental registry '
        'migrations a restored old-schema database is missing', () async {
      // Simulate the state right after an old backup ZIP has been extracted
      // and reopened: schema.sql applied, user_version pinned at the frozen
      // target, but none of the post-v1 MigrationRegistry migrations applied.
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await applySchemaOnly(db);
      await db.execute('PRAGMA user_version = ${DatabaseConfig.databaseVersion}');
      DatabaseService.setTestDatabase(db);

      // Precondition: the frozen v1 schema predates these post-v1 objects, so
      // they are absent — exactly the state a backup taken under an older build
      // is restored into. (If they were already present the test could not
      // distinguish the bug from the fix.)
      expect(await tableExists(db, 'activity_events'), isFalse);
      expect(await tableExists(db, 'project_publication'), isFalse);
      expect(
          await columnExists(db, 'translation_versions', 'validation_schema_version'),
          isFalse);

      // Run the SAME reinitializer production uses after a restore when no
      // override is injected (DatabaseBackupService._defaultReinitialize).
      await DatabaseBackupService.defaultReinitializeForTesting();

      // After the restore the schema must be complete for exactly the
      // tables/columns the app queries on the Activity, Projects/Publish and
      // editor screens. The bug: the reinitializer skipped
      // ensurePerformanceIndexes, and runMigrations no-ops because user_version
      // already equals the frozen target — so these objects stayed missing and
      // the first query touching them threw until the next full app restart.
      expect(await tableExists(db, 'activity_events'), isTrue,
          reason: 'activity_events must exist after restore, else Activity '
              'queries throw');
      expect(await tableExists(db, 'project_publication'), isTrue,
          reason: 'project_publication must exist after restore, else Publish '
              'throws');
      expect(
          await columnExists(db, 'translation_versions', 'validation_schema_version'),
          isTrue,
          reason: 'validation_schema_version must exist after restore, else the '
              'editor grid throws');

      await db.close();
      DatabaseService.resetTestDatabase();
    });
  });

  group('restore safety net', () {
    test(
        'reinitializes the database and reports an error when the safety '
        'backup cannot be created', () async {
      final dbDir = await Directory(p.join(tempRoot.path, 'dbdir')).create();
      final dbPath = p.join(dbDir.path, DatabaseConfig.databaseName);
      final currentDb = await databaseFactory.openDatabase(dbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      await currentDb.insert('items', {'v': 'original-row'});
      await currentDb
          .execute('PRAGMA user_version = ${DatabaseConfig.databaseVersion}');

      // A perfectly valid backup archive...
      final backupDbBytes = await buildDatabaseBytes(
        userVersion: DatabaseConfig.databaseVersion,
      );
      final zipPath = await writeBackupZip(p.join(tempRoot.path, 'ok.zip'), {
        DatabaseConfig.databaseName: backupDbBytes,
      });

      // ...but the safety .bak cannot be created: block its path with a
      // directory so File.copy fails after the database has been closed.
      await Directory('$dbPath.bak').create(recursive: true);

      var reinitCalls = 0;
      Database? reopened;
      final service = DatabaseBackupService(
        databasePathProvider: () async => dbPath,
        databaseCloser: () async => currentDb.close(),
        databaseReinitializer: () async {
          reinitCalls++;
          reopened = await databaseFactory.openDatabase(dbPath);
          DatabaseService.setTestDatabase(reopened!);
        },
      );
      final result = await service.restoreBackup(zipPath);

      expect(result.isErr, isTrue);
      expect(result.unwrapErr().message, contains('safety backup'));
      expect(result.unwrapErr().requiresRestart, isFalse,
          reason: 'the database was reinitialized, no restart needed');
      expect(reinitCalls, 1,
          reason: 'the database must not be left closed when the safety '
              'backup fails');

      // The original database is untouched and reopened.
      final rows = await reopened!.query('items', orderBy: 'id');
      expect(rows.map((r) => r['v']).toList(), ['original-row']);

      await reopened!.close();
      DatabaseService.resetTestDatabase();
    });

    test(
        'successful restore extracts atomically and leaves no .restore-tmp '
        'files behind', () async {
      // Build a backup from a WAL source database.
      final sourceDir =
          await Directory(p.join(tempRoot.path, 'source')).create();
      final sourceDbPath = p.join(sourceDir.path, DatabaseConfig.databaseName);
      db = await openWalDatabase(sourceDbPath, rowCount: 12, tag: 'from_backup');

      final zipPath = p.join(tempRoot.path, 'backup.zip');
      final backupService = DatabaseBackupService(
        databasePathProvider: () async => sourceDbPath,
      );
      expect((await backupService.createBackup(zipPath)).isOk, isTrue);
      await db!.close();
      db = null;
      DatabaseService.resetTestDatabase();

      // Restore over a different current database.
      final currentDir =
          await Directory(p.join(tempRoot.path, 'current')).create();
      final currentDbPath =
          p.join(currentDir.path, DatabaseConfig.databaseName);
      final currentDb = await databaseFactory.openDatabase(currentDbPath);
      await currentDb
          .execute('CREATE TABLE items (id INTEGER PRIMARY KEY, v TEXT)');
      await currentDb.insert('items', {'v': 'current-data'});

      Database? reopened;
      final restoreService = DatabaseBackupService(
        databasePathProvider: () async => currentDbPath,
        databaseCloser: () async => currentDb.close(),
        databaseReinitializer: () async {
          reopened = await databaseFactory.openDatabase(currentDbPath);
          DatabaseService.setTestDatabase(reopened!);
        },
      );
      final result = await restoreService.restoreBackup(zipPath);
      expect(result.isOk, isTrue, reason: result.toString());

      // The restored database carries the backup's rows.
      final rows = await reopened!.query('items', orderBy: 'id');
      expect(rows.length, 12);
      expect(rows.map((r) => r['v'] as String),
          everyElement(startsWith('from_backup-')));

      // No intermediate extraction files survive a successful restore.
      final leftovers = await currentDir
          .list()
          .map((e) => p.basename(e.path))
          .where((name) => name.endsWith('.restore-tmp'))
          .toList();
      expect(leftovers, isEmpty,
          reason: 'extraction temp files must not outlive the restore');

      await reopened!.close();
      DatabaseService.resetTestDatabase();
    });

    test('verifyBackupCopy throws when the copy length differs from the source',
        () async {
      final sourcePath = p.join(tempRoot.path, 'src.bin');
      final backupPath = '$sourcePath.bak';
      await File(sourcePath).writeAsBytes(List<int>.filled(1000, 1));
      await File(backupPath).writeAsBytes(List<int>.filled(999, 1));

      await expectLater(
        DatabaseBackupService.verifyBackupCopy(sourcePath, backupPath),
        throwsA(isA<BackupException>().having(
          (e) => e.message,
          'message',
          contains('Safety backup verification failed'),
        )),
        reason: 'a truncated safety copy must abort the restore',
      );

      // A complete copy passes verification.
      await File(backupPath).writeAsBytes(List<int>.filled(1000, 1));
      await DatabaseBackupService.verifyBackupCopy(sourcePath, backupPath);
    });
  });
}
