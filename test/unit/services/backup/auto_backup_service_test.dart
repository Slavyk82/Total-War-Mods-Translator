import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/backup/auto_backup_service.dart';
import 'package:twmt/services/backup/database_backup_service.dart';

import '../../../helpers/noop_logger.dart';

void main() {
  late Directory backupDir;
  late int createCalls;

  setUp(() async {
    backupDir = await Directory.systemTemp.createTemp('twmt_autobackup_test_');
    createCalls = 0;
  });

  tearDown(() async {
    if (await backupDir.exists()) {
      await backupDir.delete(recursive: true);
    }
  });

  /// Fake createBackup that just writes a small placeholder file at the
  /// destination so list/prune logic has real files to operate on.
  Future<Result<String, BackupException>> fakeCreate(String destination) async {
    createCalls++;
    await File(destination).writeAsString('zip');
    return Ok(destination);
  }

  AutoBackupService build({
    Duration minInterval = const Duration(days: 1),
    int retain = 5,
    DateTime Function()? now,
    Future<Result<String, BackupException>> Function(String)? createBackup,
  }) {
    return AutoBackupService(
      logging: NoopLogger(),
      backupDirectoryProvider: () async => backupDir.path,
      createBackup: createBackup ?? fakeCreate,
      now: now,
      minInterval: minInterval,
      retain: retain,
    );
  }

  Future<List<String>> backupFiles() async {
    final names = <String>[];
    await for (final e in backupDir.list()) {
      if (e is File) names.add(path.basename(e.path));
    }
    names.sort();
    return names;
  }

  test('creates a backup when the directory is empty', () async {
    final service = build();

    final result = await service.runIfDue();

    expect(result, isNotNull);
    expect(createCalls, 1);
    final files = await backupFiles();
    expect(files, hasLength(1));
    expect(files.single, matches(r'^TWMT_Backup_.*\.zip$'));
  });

  test('skips when a recent backup already exists', () async {
    // Plant a fresh backup, then run with a 1-day interval.
    await File(path.join(backupDir.path, 'TWMT_Backup_2026-06-14_120000.zip'))
        .writeAsString('zip');

    final service = build(minInterval: const Duration(days: 1));
    final result = await service.runIfDue();

    expect(result, isNull);
    expect(createCalls, 0);
  });

  test('takes a new backup when the newest is older than minInterval',
      () async {
    final old = File(
      path.join(backupDir.path, 'TWMT_Backup_2026-06-01_120000.zip'),
    );
    await old.writeAsString('zip');
    await old.setLastModified(DateTime(2026, 6, 1, 12));

    final service = build(
      minInterval: const Duration(days: 1),
      now: () => DateTime(2026, 6, 14, 12),
    );
    final result = await service.runIfDue();

    expect(result, isNotNull);
    expect(createCalls, 1);
  });

  test('prunes old backups beyond the retain count', () async {
    // Pre-seed 4 old backups with increasing mtimes, retain = 2.
    for (var i = 1; i <= 4; i++) {
      final f = File(
        path.join(backupDir.path, 'TWMT_Backup_2026-06-0${i}_120000.zip'),
      );
      await f.writeAsString('zip');
      await f.setLastModified(DateTime(2026, 6, i, 12));
    }

    final service = build(
      retain: 2,
      minInterval: const Duration(days: 1),
      now: () => DateTime(2026, 6, 14, 12),
    );

    await service.runIfDue();

    // After creating the new one (5 total) and pruning to 2, only the 2 newest
    // remain: the freshly created backup + the Jun 04 one.
    final files = await backupFiles();
    expect(files, hasLength(2));
    expect(files.any((f) => f.contains('2026-06-01')), isFalse);
    expect(files.any((f) => f.contains('2026-06-02')), isFalse);
  });
}
