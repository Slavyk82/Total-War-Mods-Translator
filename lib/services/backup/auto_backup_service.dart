import 'dart:io';

import 'package:path/path.dart' as path;

import '../../models/common/result.dart';
import '../shared/i_logging_service.dart';
import 'database_backup_service.dart';

/// Creates rolling, timestamped database backups at application startup.
///
/// [runIfDue] takes a fresh backup only when the newest existing auto-backup is
/// older than [minInterval], then prunes the directory down to the most recent
/// [retain] archives. It is intentionally best-effort: any failure is logged
/// and swallowed so a backup problem can never block startup or the UI.
///
/// Pure Dart by design (no Riverpod / Flutter imports) so it stays inside the
/// services layer. It depends on small function types — not the concrete
/// [DatabaseBackupService] — so it is trivially testable in isolation; the
/// wiring lives in the providers/UI layer.
class AutoBackupService {
  final ILoggingService _logging;
  final Future<String> Function() _backupDirectoryProvider;
  final Future<Result<String, BackupException>> Function(String destination)
      _createBackup;
  final DateTime Function() _now;

  /// Minimum age of the newest backup before a new one is taken.
  final Duration minInterval;

  /// How many of the most recent auto-backups to keep.
  final int retain;

  AutoBackupService({
    required ILoggingService logging,
    required Future<String> Function() backupDirectoryProvider,
    required Future<Result<String, BackupException>> Function(String destination)
        createBackup,
    DateTime Function()? now,
    this.minInterval = const Duration(days: 1),
    this.retain = 5,
  })  : _logging = logging,
        _backupDirectoryProvider = backupDirectoryProvider,
        _createBackup = createBackup,
        _now = now ?? DateTime.now;

  /// Auto-backups use a DISTINCT `TWMT_AutoBackup_*.zip` prefix so that
  /// pruning (and the "is a backup due?" check) can never match a manually
  /// saved `TWMT_Backup_*.zip` archive - deleting a user's manual backups
  /// would be data loss.
  static final RegExp _backupNamePattern =
      RegExp(r'^TWMT_AutoBackup_.*\.zip$', caseSensitive: false);

  /// Create a backup if one is due. Returns the created backup path, or null
  /// when the run was skipped (recent backup exists) or failed.
  Future<String?> runIfDue() async {
    try {
      final dirPath = await _backupDirectoryProvider();
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final existing = await _listBackupsNewestFirst(dir);
      if (existing.isNotEmpty) {
        final age = _now().difference(await existing.first.lastModified());
        if (age < minInterval) {
          _logging.debug('Auto-backup skipped: recent backup exists', {
            'ageMinutes': age.inMinutes,
            'minIntervalMinutes': minInterval.inMinutes,
          });
          return null;
        }
      }

      final destination = path.join(dirPath, _generateFilename());
      _logging.info('Starting automatic database backup', {
        'destination': destination,
      });

      final result = await _createBackup(destination);
      if (result.isErr) {
        _logging.warning('Automatic backup failed', {
          'error': result.error.message,
        });
        return null;
      }

      _logging.info('Automatic database backup created', {'path': result.value});
      await _pruneOldBackups(dir);
      return result.value;
    } catch (e) {
      // Best-effort: never let a backup failure surface to the user/startup.
      _logging.warning('Automatic backup failed', {'error': e.toString()});
      return null;
    }
  }

  /// Filename in the format `TWMT_AutoBackup_YYYY-MM-DD_HHMMSS.zip`. The
  /// `AutoBackup` infix distinguishes rolling auto-backups from user-initiated
  /// `TWMT_Backup_*` archives so pruning never touches the latter.
  String _generateFilename() {
    String two(int v) => v.toString().padLeft(2, '0');
    final n = _now();
    final stamp = '${n.year}-${two(n.month)}-${two(n.day)}_'
        '${two(n.hour)}${two(n.minute)}${two(n.second)}';
    return 'TWMT_AutoBackup_$stamp.zip';
  }

  /// List `TWMT_Backup_*.zip` files in [dir], newest (most recently modified)
  /// first.
  Future<List<File>> _listBackupsNewestFirst(Directory dir) async {
    final withTimes = <(File, DateTime)>[];
    await for (final entity in dir.list()) {
      if (entity is File &&
          _backupNamePattern.hasMatch(path.basename(entity.path))) {
        withTimes.add((entity, await entity.lastModified()));
      }
    }
    withTimes.sort((a, b) => b.$2.compareTo(a.$2));
    return withTimes.map((e) => e.$1).toList(growable: false);
  }

  /// Delete auto-backups beyond the most recent [retain].
  Future<void> _pruneOldBackups(Directory dir) async {
    final backups = await _listBackupsNewestFirst(dir);
    if (backups.length <= retain) return;
    for (final stale in backups.skip(retain)) {
      try {
        await stale.delete();
        _logging.debug('Pruned old auto-backup', {'path': stale.path});
      } catch (e) {
        _logging.warning('Failed to prune old auto-backup', {
          'path': stale.path,
          'error': e.toString(),
        });
      }
    }
  }
}
