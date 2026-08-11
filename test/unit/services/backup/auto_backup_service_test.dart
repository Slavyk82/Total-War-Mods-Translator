import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/models/backup/backup_progress.dart';
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
  Future<Result<String, BackupException>> fakeCreate(
    String destination, {
    void Function(BackupProgress)? onProgress,
  }) async {
    createCalls++;
    await File(destination).writeAsString('zip');
    return Ok(destination);
  }

  AutoBackupService build({
    Duration minInterval = const Duration(days: 1),
    int retain = 5,
    DateTime Function()? now,
    Future<Result<String, BackupException>> Function(
      String, {
      void Function(BackupProgress)? onProgress,
    })? createBackup,
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

  /// Builds the service WITHOUT passing `minInterval`, so the tests using it
  /// pin the production default instead of a value the test picked itself.
  AutoBackupService buildWithDefaultInterval({DateTime Function()? now}) {
    return AutoBackupService(
      logging: NoopLogger(),
      backupDirectoryProvider: () async => backupDir.path,
      createBackup: fakeCreate,
      now: now,
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

    expect(result, isA<AutoBackupCreated>());
    expect(createCalls, 1);
    final files = await backupFiles();
    expect(files, hasLength(1));
    expect(files.single, matches(r'^TWMT_AutoBackup_.*\.zip$'));
  });

  test('skips when a recent backup already exists', () async {
    // Plant a fresh auto-backup, then run with a 1-day interval.
    await File(
      path.join(backupDir.path, 'TWMT_AutoBackup_2026-06-14_120000.zip'),
    ).writeAsString('zip');

    final service = build(minInterval: const Duration(days: 1));
    final result = await service.runIfDue();

    expect(result, isA<AutoBackupSkipped>());
    expect(createCalls, 0);
  });

  test('takes a new backup when the newest is older than minInterval',
      () async {
    final old = File(
      path.join(backupDir.path, 'TWMT_AutoBackup_2026-06-01_120000.zip'),
    );
    await old.writeAsString('zip');
    await old.setLastModified(DateTime(2026, 6, 1, 12));

    final service = build(
      minInterval: const Duration(days: 1),
      now: () => DateTime(2026, 6, 14, 12),
    );
    final result = await service.runIfDue();

    expect(result, isA<AutoBackupCreated>());
    expect(createCalls, 1);
  });

  // The default interval is deliberately a week, not a day: a backup on every
  // launch is pure noise for a user who opens the app several times a day.
  group('default interval (7 days)', () {
    test('is a week', () {
      expect(buildWithDefaultInterval().minInterval, const Duration(days: 7));
    });

    test('still creates the very first backup when none exists', () async {
      final result = await buildWithDefaultInterval().runIfDue();

      expect(result, isA<AutoBackupCreated>());
      expect(createCalls, 1);
    });

    test('skips when the newest backup is 3 days old', () async {
      final recent = File(
        path.join(backupDir.path, 'TWMT_AutoBackup_2026-06-11_120000.zip'),
      );
      await recent.writeAsString('zip');
      await recent.setLastModified(DateTime(2026, 6, 11, 12));

      final result = await buildWithDefaultInterval(
        now: () => DateTime(2026, 6, 14, 12),
      ).runIfDue();

      expect(result, isA<AutoBackupSkipped>());
      expect(createCalls, 0);
    });

    test('backs up when the newest backup is 8 days old', () async {
      final stale = File(
        path.join(backupDir.path, 'TWMT_AutoBackup_2026-06-06_120000.zip'),
      );
      await stale.writeAsString('zip');
      await stale.setLastModified(DateTime(2026, 6, 6, 12));

      final result = await buildWithDefaultInterval(
        now: () => DateTime(2026, 6, 14, 12),
      ).runIfDue();

      expect(result, isA<AutoBackupCreated>());
      expect(createCalls, 1);
    });
  });

  test('prunes old backups beyond the retain count', () async {
    // Pre-seed 4 old auto-backups with increasing mtimes, retain = 2.
    for (var i = 1; i <= 4; i++) {
      final f = File(
        path.join(backupDir.path, 'TWMT_AutoBackup_2026-06-0${i}_120000.zip'),
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

  // Regression (D1): manual backups (saved by the user with the TWMT_Backup_
  // name) live in the same directory but must NEVER be deleted by auto-backup
  // pruning. Only auto-backups are subject to the retain limit.
  test('never prunes manually-named backups, only auto-backups', () async {
    // Four manual backups the user saved into the backup directory.
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

    final files = await backupFiles();
    // All four manual backups survive; pruning only ever touches auto-backups.
    final manual = files.where((f) => f.startsWith('TWMT_Backup_')).toList();
    expect(manual, hasLength(4));
  });

  test('reports a failed backup as AutoBackupFailure', () async {
    final service = build(
      createBackup: (destination, {onProgress}) async =>
          const Err(BackupException('disk on fire')),
    );

    final result = await service.runIfDue();

    expect(result, isA<AutoBackupFailure>());
    expect((result as AutoBackupFailure).message, contains('disk on fire'));
  });

  test('reports a thrown error as AutoBackupFailure', () async {
    final service = build(
      createBackup: (destination, {onProgress}) async =>
          throw StateError('boom'),
    );

    final result = await service.runIfDue();

    expect(result, isA<AutoBackupFailure>());
  });

  test('exposes the created path', () async {
    final service = build();

    final result = await service.runIfDue();

    expect(result, isA<AutoBackupCreated>());
    expect((result as AutoBackupCreated).path, endsWith('.zip'));
  });

  test('forwards onProgress to the underlying backup', () async {
    BackupProgress? seen;
    final service = build(
      createBackup: (destination, {onProgress}) async {
        onProgress?.call(
          const BackupProgress(phase: BackupPhase.compressing, bytesDone: 5),
        );
        await File(destination).writeAsString('zip');
        return Ok(destination);
      },
    );

    await service.runIfDue(onProgress: (p) => seen = p);

    expect(seen, isNotNull);
    expect(seen!.bytesDone, 5);
  });
}
