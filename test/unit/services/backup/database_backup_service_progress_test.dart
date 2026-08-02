import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/backup/backup_progress.dart';
import 'package:twmt/services/backup/database_backup_service.dart';

import '../../../helpers/noop_logger.dart';

Uint8List fakeSqliteBytes(int payloadSize, {int userVersion = 1, int seed = 7}) {
  final bytes = Uint8List(100 + payloadSize);
  const magic = 'SQLite format 3';
  for (var i = 0; i < magic.length; i++) {
    bytes[i] = magic.codeUnitAt(i);
  }
  bytes[15] = 0x00;
  bytes[60] = (userVersion >> 24) & 0xff;
  bytes[61] = (userVersion >> 16) & 0xff;
  bytes[62] = (userVersion >> 8) & 0xff;
  bytes[63] = userVersion & 0xff;
  final rnd = Random(seed);
  for (var i = 100; i < bytes.length; i++) {
    bytes[i] = rnd.nextInt(256);
  }
  return bytes;
}

void main() {
  late Directory tmp;
  late String dbPath;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('twmt_backup_progress_test_');
    dbPath = path.join(tmp.path, 'twmt.db');
    await File(dbPath).writeAsBytes(fakeSqliteBytes(6 * 1024 * 1024));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DatabaseBackupService build() => DatabaseBackupService(
        logging: NoopLogger(),
        databasePathProvider: () async => dbPath,
        databaseCloser: () async {},
        databaseReinitializer: () async {},
        progressInterval: const Duration(milliseconds: 5),
      );

  test('reports compressing progress and still succeeds', () async {
    final events = <BackupProgress>[];
    final destination = path.join(tmp.path, 'backup.zip');

    final result =
        await build().createBackup(destination, onProgress: events.add);

    expect(result.isOk, isTrue);
    expect(
      events.any((e) => e.phase == BackupPhase.compressing),
      isTrue,
      reason: 'the immediate emission guarantees at least one event',
    );
  });

  test('byte counts never decrease within the compressing phase', () async {
    final events = <BackupProgress>[];
    final destination = path.join(tmp.path, 'backup.zip');

    await build().createBackup(destination, onProgress: events.add);

    final compressing = events
        .where((e) => e.phase == BackupPhase.compressing)
        .map((e) => e.bytesDone)
        .toList();
    for (var i = 1; i < compressing.length; i++) {
      expect(compressing[i], greaterThanOrEqualTo(compressing[i - 1]));
    }
  });

  test('stops reporting once the backup has returned', () async {
    final events = <BackupProgress>[];
    final destination = path.join(tmp.path, 'backup.zip');

    await build().createBackup(destination, onProgress: events.add);
    // Positive precondition first: a successful backup compresses a 6 MB
    // fake database, which takes long enough (isolate spawn alone costs
    // several ms) that the immediate emission is reliably delivered before
    // createBackup returns. Without this, a poller that emits nothing at all
    // would pass the negative assertion below unchanged.
    expect(events, isNotEmpty);
    final countAtReturn = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(events.length, countAtReturn);
  });

  test('stops reporting when the backup fails', () async {
    final events = <BackupProgress>[];
    // Occupy the worker's temp path with a directory so its first
    // OutputFileStream open throws. A non-existent parent directory would NOT
    // fail — createBackup creates those recursively.
    final destination = path.join(tmp.path, 'backup.zip');
    await Directory('$destination.tmp').create();

    final result =
        await build().createBackup(destination, onProgress: events.add);
    expect(result.isErr, isTrue);
    // No positive "at least one event" assertion here, deliberately: the
    // worker fails almost as soon as the isolate spawns (opening a directory
    // as a file), which genuinely races the immediate emission's own async
    // file-stat hop. Either order is possible, so asserting events.isNotEmpty
    // would itself be flaky. The generation guard in BackupProgressPoller
    // (see backup_progress_poller_test.dart) already covers "a stale sample
    // must not leak past stop()"; this test only needs the negative half:
    // whatever did or didn't fire before the return, nothing fires after it.
    final countAtReturn = events.length;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(events.length, countAtReturn);
  });

  test('works with no onProgress supplied', () async {
    final destination = path.join(tmp.path, 'backup.zip');
    final result = await build().createBackup(destination);
    expect(result.isOk, isTrue);
  });
}
