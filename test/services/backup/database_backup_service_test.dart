import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:twmt/config/database_config.dart';
import 'package:twmt/services/backup/database_backup_service.dart';
import 'package:twmt/services/database/database_service.dart';

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
}
