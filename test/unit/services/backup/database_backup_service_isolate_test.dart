import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/services/backup/database_backup_service.dart';

import '../../../helpers/noop_logger.dart';

/// A file that passes DatabaseBackupService's SQLite header validation: the
/// magic string, a zero byte at offset 15, and a non-zero `user_version` at
/// offset 60 (big-endian 32-bit).
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
    tmp = await Directory.systemTemp.createTemp('twmt_backup_isolate_test_');
    dbPath = path.join(tmp.path, 'twmt.db');
    await File(dbPath).writeAsBytes(fakeSqliteBytes(4 * 1024 * 1024));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  DatabaseBackupService build() => DatabaseBackupService(
        logging: NoopLogger(),
        databasePathProvider: () async => dbPath,
        databaseCloser: () async {},
        databaseReinitializer: () async {},
      );

  test('creates a valid backup with the worker running in an isolate',
      () async {
    final destination = path.join(tmp.path, 'backup.zip');

    final result = await build().createBackup(destination);

    expect(result.isOk, isTrue);
    expect(await File(destination).exists(), isTrue);

    final validated = await build().validateBackup(destination);
    expect(validated.isOk, isTrue);
    expect(validated.value.hasDatabaseFile, isTrue);
  });

  test('keeps the calling isolate responsive during compression', () async {
    // 64 MB of incompressible data: large enough that a synchronous deflate
    // stalls the event loop for a clearly measurable stretch.
    await File(dbPath).writeAsBytes(fakeSqliteBytes(64 * 1024 * 1024));
    final destination = path.join(tmp.path, 'backup.zip');

    // Sample the wall clock on a fast timer and keep the largest gap between
    // consecutive ticks.
    //
    // Counting ticks would prove nothing: createBackup awaits file I/O either
    // way, so some ticks always get through even when compression blocks the
    // isolate. The GAP is the discriminating signal — while Deflate.finish()
    // holds the isolate, no tick can fire at all.
    final ticks = <DateTime>[DateTime.now()];
    final timer = Timer.periodic(
      const Duration(milliseconds: 5),
      (_) => ticks.add(DateTime.now()),
    );

    final result = await build().createBackup(destination);
    timer.cancel();

    expect(result.isOk, isTrue);

    var maxGapMs = 0;
    for (var i = 1; i < ticks.length; i++) {
      final gap = ticks[i].difference(ticks[i - 1]).inMilliseconds;
      if (gap > maxGapMs) maxGapMs = gap;
    }
    expect(
      maxGapMs,
      lessThan(500),
      reason: 'the event loop stalled for ${maxGapMs}ms, so compression is '
          'still running on the calling isolate',
    );
  });

  test('surfaces a worker failure as Err rather than throwing', () async {
    final destination = path.join(tmp.path, 'backup.zip');
    // Block the temp zip path with a pre-existing directory so the worker's
    // OutputFileStream fails to open it. (A destination inside a missing
    // parent directory would NOT force a failure here: createBackup creates
    // missing parent directories recursively before writing anything.)
    await Directory('$destination.tmp').create(recursive: true);

    final result = await build().createBackup(destination);

    expect(result.isErr, isTrue);
  });

  test('leaves no .tmp file behind when the backup fails', () async {
    final destination = path.join(tmp.path, 'backup.zip');
    // Block the FINAL destination (not the .tmp path) with a pre-existing
    // directory. This lets compression run to completion and write a real,
    // complete `$destination.tmp` file; only the final
    // `File(tempZipPath).rename(destinationPath)` fails, because you cannot
    // rename a file onto an existing directory. That failure is what the
    // cleanup logic in createBackup's `finally` is actually meant to handle:
    // a genuine leftover .tmp file, not a directory that blocked the write
    // before any file existed (which is what a directory-at-.tmp blocker
    // would give us — see the "surfaces a worker failure" test above, which
    // is testing something else and does not need a real leftover file).
    await Directory(destination).create();

    final result = await build().createBackup(destination);

    expect(result.isErr, isTrue);
    // Pins that the failure really came from the rename, not from something
    // earlier (e.g. the parent-directory check or the database-file check).
    expect(await Directory(destination).exists(), isTrue);

    final leftovers = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'))
        .toList();
    expect(leftovers, isEmpty);
  });
}
