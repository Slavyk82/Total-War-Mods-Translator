import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

import '../../config/database_config.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../database/database_service.dart';
import '../database/migration_service.dart';
import '../service_locator.dart';
import '../shared/i_logging_service.dart';

/// Exception thrown when backup operations fail.
class BackupException extends ServiceException {
  final bool requiresRestart;

  const BackupException(
    super.message, {
    this.requiresRestart = false,
    super.error,
    super.stackTrace,
  });
}

/// Information about a backup file.
class BackupInfo {
  final String filePath;
  final DateTime? createdAt;
  final int fileSize;
  final bool hasDatabaseFile;
  final bool hasWalFile;
  final bool hasShmFile;

  const BackupInfo({
    required this.filePath,
    this.createdAt,
    required this.fileSize,
    required this.hasDatabaseFile,
    required this.hasWalFile,
    required this.hasShmFile,
  });

  bool get isValid => hasDatabaseFile;
}

/// Service for creating and restoring database backups.
///
/// Creates ZIP archives containing the SQLite database files (twmt.db,
/// twmt.db-wal, twmt.db-shm) and restores from those archives.
class DatabaseBackupService {
  final ILoggingService _logging;
  final Future<String> Function() _getDatabasePath;
  final Future<void> Function() _closeDatabase;
  final Future<void> Function() _reinitializeDatabase;

  /// Test-only escape hatch that forces the legacy checkpoint-and-copy
  /// snapshot path even when `VACUUM INTO` is available.
  @visibleForTesting
  final bool debugForceLegacySnapshot;

  DatabaseBackupService({
    ILoggingService? logging,
    Future<String> Function()? databasePathProvider,
    Future<void> Function()? databaseCloser,
    Future<void> Function()? databaseReinitializer,
    this.debugForceLegacySnapshot = false,
  })  : _logging = logging ?? ServiceLocator.get<ILoggingService>(),
        _getDatabasePath =
            databasePathProvider ?? DatabaseConfig.getDatabasePath,
        _closeDatabase = databaseCloser ?? DatabaseService.close,
        _reinitializeDatabase = databaseReinitializer ?? _defaultReinitialize;

  static Future<void> _defaultReinitialize() async {
    await DatabaseService.initialize();
    await MigrationService.runMigrations();
  }

  /// Generate a suggested filename for a backup.
  ///
  /// Returns a filename in the format: TWMT_Backup_YYYY-MM-DD_HHMMSS.zip
  String generateBackupFilename() {
    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd_HHmmss');
    return 'TWMT_Backup_${formatter.format(now)}.zip';
  }

  /// Create a backup of the database.
  ///
  /// [destinationPath] should be the full path including filename.
  /// Returns the path to the created backup file.
  ///
  /// When the database is open, the backup is taken with `VACUUM INTO`,
  /// which produces a transactionally consistent, self-contained snapshot
  /// even while concurrent writers (e.g. a running translation batch) keep
  /// modifying the database. The archive is first written to a temporary
  /// file next to [destinationPath] and then renamed over the final name,
  /// so an interrupted backup never leaves a half-written file that looks
  /// like a valid archive.
  Future<Result<String, BackupException>> createBackup(
    String destinationPath,
  ) async {
    _logging.info('Creating database backup', {'destination': destinationPath});

    Directory? snapshotDir;
    final tempZipPath = '$destinationPath.tmp';
    var tempZipNeedsCleanup = false;

    try {
      // Ensure parent directory exists
      final parentDir = Directory(path.dirname(destinationPath));
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Get database paths
      final dbPath = await _getDatabasePath();

      // Check that main database exists
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return Err(const BackupException('Database file not found'));
      }

      // Create archive
      final archive = Archive();

      final useVacuumInto = DatabaseService.isInitialized &&
          !debugForceLegacySnapshot &&
          await _isVacuumIntoSupported();

      if (useVacuumInto) {
        // VACUUM INTO runs as a single read transaction on the connection's
        // statement queue, so the snapshot is consistent regardless of
        // concurrent writers and never pairs a stale main file with a
        // mismatched WAL.
        snapshotDir = await Directory.systemTemp.createTemp('twmt_backup_');
        final snapshotPath =
            path.join(snapshotDir.path, DatabaseConfig.databaseName);
        _logging.debug('Creating consistent snapshot via VACUUM INTO');
        await DatabaseService.database
            .execute('VACUUM INTO ?', [snapshotPath]);
        final dbBytes = await File(snapshotPath).readAsBytes();
        archive.addFile(ArchiveFile(
          DatabaseConfig.databaseName,
          dbBytes.length,
          dbBytes,
        ));
      } else {
        if (DatabaseService.isInitialized) {
          // Legacy fallback (SQLite < 3.27): force a verified TRUNCATE
          // checkpoint so the main file is complete. If the checkpoint
          // cannot finish, the WAL/SHM files are copied alongside the main
          // file below so the backup set stays self-consistent.
          await _checkpointForBackup();
        }
        // When the database is closed the files are quiescent and a plain
        // copy of the db/WAL/SHM set is safe.
        await _addDatabaseFilesToArchive(archive, dbPath);
      }

      // Encode and write archive atomically: temp file first, then rename.
      _logging.debug('Writing backup archive');
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        return Err(const BackupException('Failed to create ZIP archive'));
      }

      final tempZipFile = File(tempZipPath);
      tempZipNeedsCleanup = true;
      await tempZipFile.writeAsBytes(zipBytes, flush: true);
      await tempZipFile.rename(destinationPath);
      tempZipNeedsCleanup = false;

      final fileSize = await File(destinationPath).length();
      _logging.info('Backup created successfully', {
        'path': destinationPath,
        'size': fileSize,
      });

      return Ok(destinationPath);
    } catch (e, stackTrace) {
      _logging.error('Failed to create backup', e, stackTrace);
      return Err(BackupException(
        'Failed to create backup: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    } finally {
      if (tempZipNeedsCleanup) {
        try {
          final tempZipFile = File(tempZipPath);
          if (await tempZipFile.exists()) {
            await tempZipFile.delete();
          }
        } catch (e) {
          _logging.warning('Failed to delete temporary backup file', {
            'path': tempZipPath,
            'error': e.toString(),
          });
        }
      }
      if (snapshotDir != null) {
        try {
          await snapshotDir.delete(recursive: true);
        } catch (e) {
          _logging.warning('Failed to delete snapshot directory', {
            'path': snapshotDir.path,
            'error': e.toString(),
          });
        }
      }
    }
  }

  /// Check whether the linked SQLite library supports `VACUUM INTO`
  /// (requires SQLite 3.27, released 2019-02-07).
  Future<bool> _isVacuumIntoSupported() async {
    try {
      final rows = await DatabaseService.database
          .rawQuery('SELECT sqlite_version() AS version');
      final version = (rows.first['version'] as String?) ?? '';
      final parts = version.split('.');
      final major = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
      final minor = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (major == null || minor == null) {
        return false;
      }
      final supported = major > 3 || (major == 3 && minor >= 27);
      if (!supported) {
        _logging.warning(
          'SQLite does not support VACUUM INTO, '
          'falling back to checkpoint-and-copy backup',
          {'sqliteVersion': version},
        );
      }
      return supported;
    } catch (e) {
      _logging.warning(
        'Could not determine SQLite version, '
        'falling back to checkpoint-and-copy backup',
        {'error': e.toString()},
      );
      return false;
    }
  }

  /// Run a TRUNCATE checkpoint and verify its result before a file-copy
  /// backup, retrying briefly if SQLite reports it could not finish
  /// (busy != 0). If the checkpoint still cannot complete, the caller copies
  /// the WAL and SHM files alongside the main file so the set stays coherent.
  Future<void> _checkpointForBackup() async {
    const maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final result = await DatabaseService.database
            .rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        final row =
            result.isNotEmpty ? result.first : const <String, Object?>{};
        final busy = (row['busy'] as int?) ?? 1;
        if (busy == 0) {
          _logging.debug('WAL fully checkpointed before backup', {
            'attempt': attempt,
          });
          return;
        }
        _logging.debug('WAL checkpoint reported busy, retrying', {
          'attempt': attempt,
        });
      } catch (e) {
        _logging.warning('WAL checkpoint before backup failed', {
          'attempt': attempt,
          'error': e.toString(),
        });
      }
      if (attempt < maxAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    _logging.warning(
      'WAL could not be fully checkpointed; '
      'including WAL/SHM files in backup to keep the set consistent',
    );
  }

  /// Add the database file and its WAL/SHM sidecar files to [archive].
  Future<void> _addDatabaseFilesToArchive(
    Archive archive,
    String dbPath,
  ) async {
    _logging.debug('Adding database file to archive');
    final dbBytes = await File(dbPath).readAsBytes();
    archive.addFile(ArchiveFile(
      DatabaseConfig.databaseName,
      dbBytes.length,
      dbBytes,
    ));

    final walFile = File('$dbPath-wal');
    if (await walFile.exists()) {
      _logging.debug('Adding WAL file to archive');
      final walBytes = await walFile.readAsBytes();
      archive.addFile(ArchiveFile(
        '${DatabaseConfig.databaseName}-wal',
        walBytes.length,
        walBytes,
      ));
    }

    final shmFile = File('$dbPath-shm');
    if (await shmFile.exists()) {
      _logging.debug('Adding SHM file to archive');
      final shmBytes = await shmFile.readAsBytes();
      archive.addFile(ArchiveFile(
        '${DatabaseConfig.databaseName}-shm',
        shmBytes.length,
        shmBytes,
      ));
    }
  }

  /// Validate a backup file without restoring it.
  ///
  /// Returns information about the backup contents.
  Future<Result<BackupInfo, BackupException>> validateBackup(
    String zipPath,
  ) async {
    _logging.debug('Validating backup', {'path': zipPath});

    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return Err(const BackupException('Backup file not found'));
      }

      final fileSize = await zipFile.length();
      final bytes = await zipFile.readAsBytes();

      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        return Err(BackupException('Invalid ZIP file: $e'));
      }

      // Check for required files
      bool hasDatabaseFile = false;
      bool hasWalFile = false;
      bool hasShmFile = false;

      for (final file in archive) {
        if (file.name == DatabaseConfig.databaseName) {
          hasDatabaseFile = true;
        } else if (file.name == '${DatabaseConfig.databaseName}-wal') {
          hasWalFile = true;
        } else if (file.name == '${DatabaseConfig.databaseName}-shm') {
          hasShmFile = true;
        }
      }

      final info = BackupInfo(
        filePath: zipPath,
        fileSize: fileSize,
        hasDatabaseFile: hasDatabaseFile,
        hasWalFile: hasWalFile,
        hasShmFile: hasShmFile,
      );

      if (!info.isValid) {
        return Err(const BackupException(
          'Invalid backup: missing database file (twmt.db)',
        ));
      }

      _logging.debug('Backup validated successfully', {
        'hasDatabaseFile': hasDatabaseFile,
        'hasWalFile': hasWalFile,
        'hasShmFile': hasShmFile,
      });

      return Ok(info);
    } catch (e, stackTrace) {
      _logging.error('Failed to validate backup', e, stackTrace);
      return Err(BackupException(
        'Failed to validate backup: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Restore the database from a backup.
  ///
  /// WARNING: This will replace the current database.
  /// The application may need to be restarted after restore.
  Future<Result<void, BackupException>> restoreBackup(String zipPath) async {
    _logging.info('Restoring database from backup', {'source': zipPath});

    try {
      // Validate backup first
      final validateResult = await validateBackup(zipPath);
      if (validateResult.isErr) {
        return Err(validateResult.unwrapErr());
      }

      // Read and decode ZIP
      final bytes = await File(zipPath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Get database directory
      final dbPath = await _getDatabasePath();
      final dbDir = path.dirname(dbPath);

      // Close current database connection
      _logging.debug('Closing database connection');
      await _closeDatabase();

      // Create backup of current files (safety measure)
      await _createTemporaryBackup(dbPath);

      try {
        // Extract files from archive
        _logging.debug('Extracting backup files');
        final extractedNames = <String>{};
        for (final file in archive) {
          if (file.isFile) {
            final targetPath = path.join(dbDir, file.name);
            final outputFile = File(targetPath);
            await outputFile.writeAsBytes(file.content as List<int>);
            extractedNames.add(file.name);
            _logging.debug('Extracted file', {'name': file.name});
          }
        }

        // Snapshot backups contain only the main database file. Remove any
        // leftover sidecar files so the restored database is never paired
        // with a WAL/SHM from the previous database generation (a stale WAL
        // would either be replayed into the restored database or silently
        // discarded, both of which corrupt the restore).
        for (final suffix in const ['-wal', '-shm']) {
          final sidecarName = '${DatabaseConfig.databaseName}$suffix';
          if (extractedNames.contains(sidecarName)) continue;
          final sidecarFile = File(path.join(dbDir, sidecarName));
          if (await sidecarFile.exists()) {
            await sidecarFile.delete();
            _logging.debug('Removed stale sidecar file', {
              'name': sidecarName,
            });
          }
        }

        // Reinitialize database
        _logging.debug('Reinitializing database');
        await _reinitializeDatabase();

        // Clean up temporary backup
        await _cleanupTemporaryBackup(dbPath);

        _logging.info('Database restored successfully');
        return Ok(null);
      } catch (e, stackTrace) {
        _logging.error('Failed during restore, attempting rollback', e, stackTrace);

        // Try to restore from temporary backup
        await _rollbackFromTemporaryBackup(dbPath);

        // Try to reinitialize
        try {
          await _reinitializeDatabase();
        } catch (_) {
          // If reinit fails, suggest restart
          return Err(BackupException(
            'Restore failed and database could not be reinitialized. '
            'Please restart the application.',
            requiresRestart: true,
            error: e,
            stackTrace: stackTrace,
          ));
        }

        return Err(BackupException(
          'Restore failed: $e',
          error: e,
          stackTrace: stackTrace,
        ));
      }
    } catch (e, stackTrace) {
      _logging.error('Failed to restore backup', e, stackTrace);
      return Err(BackupException(
        'Failed to restore backup: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    }
  }

  /// Create a temporary backup of current database files.
  Future<void> _createTemporaryBackup(String dbPath) async {
    final walPath = '$dbPath-wal';
    final shmPath = '$dbPath-shm';

    final dbFile = File(dbPath);
    final walFile = File(walPath);
    final shmFile = File(shmPath);

    if (await dbFile.exists()) {
      await dbFile.copy('$dbPath.bak');
    }
    if (await walFile.exists()) {
      await walFile.copy('$walPath.bak');
    }
    if (await shmFile.exists()) {
      await shmFile.copy('$shmPath.bak');
    }
  }

  /// Clean up temporary backup files.
  Future<void> _cleanupTemporaryBackup(String dbPath) async {
    final backupFiles = [
      File('$dbPath.bak'),
      File('$dbPath-wal.bak'),
      File('$dbPath-shm.bak'),
    ];

    for (final file in backupFiles) {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  /// Attempt to rollback from temporary backup.
  ///
  /// Restores every file that has a `.bak` copy, then deletes any `-wal`/
  /// `-shm` sidecar without one (i.e. that did not exist before the
  /// restore). Without that mirror-image of the forward sidecar cleanup, a
  /// legacy-format archive carrying WAL/SHM files would leave the rolled
  /// back database paired with sidecars from the backup's database
  /// generation — the same cross-generation corruption the restore path
  /// guards against.
  Future<void> _rollbackFromTemporaryBackup(String dbPath) async {
    final dbBackup = File('$dbPath.bak');
    if (await dbBackup.exists()) {
      await dbBackup.copy(dbPath);
      await dbBackup.delete();
    }

    for (final suffix in const ['-wal', '-shm']) {
      final sidecarPath = '$dbPath$suffix';
      final sidecarBackup = File('$sidecarPath.bak');
      if (await sidecarBackup.exists()) {
        await sidecarBackup.copy(sidecarPath);
        await sidecarBackup.delete();
        continue;
      }
      // No .bak means this sidecar did not exist before the restore; remove
      // anything the failed restore extracted so the rolled-back state is
      // exactly the pre-restore file set. Best-effort: a leftover sidecar
      // must not mask the original restore failure.
      try {
        final sidecarFile = File(sidecarPath);
        if (await sidecarFile.exists()) {
          await sidecarFile.delete();
          _logging.debug('Removed extracted sidecar file during rollback', {
            'path': sidecarPath,
          });
        }
      } catch (e) {
        _logging.warning('Failed to remove extracted sidecar during rollback', {
          'path': sidecarPath,
          'error': e.toString(),
        });
      }
    }
  }
}
