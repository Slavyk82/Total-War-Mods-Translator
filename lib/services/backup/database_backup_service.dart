import 'dart:io';
import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;

import '../../config/database_config.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';
import '../database/database_service.dart';
import '../database/migration_service.dart';
import '../shared/logging_service.dart';

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
  final LoggingService _logging;

  DatabaseBackupService({LoggingService? logging})
      : _logging = logging ?? LoggingService.instance;

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
  Future<Result<String, BackupException>> createBackup(
    String destinationPath,
  ) async {
    _logging.info('Creating database backup', {'destination': destinationPath});

    try {
      // Ensure parent directory exists
      final parentDir = Directory(path.dirname(destinationPath));
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      // Checkpoint WAL to ensure all data is in main database
      _logging.debug('Checkpointing WAL before backup');
      await DatabaseService.checkpointWal();

      // Get database paths
      final dbPath = await DatabaseConfig.getDatabasePath();
      final walPath = '$dbPath-wal';
      final shmPath = '$dbPath-shm';

      // Check that main database exists
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return Err(const BackupException('Database file not found'));
      }

      // Create archive
      final archive = Archive();

      // Add main database file
      _logging.debug('Adding database file to archive');
      final dbBytes = await dbFile.readAsBytes();
      archive.addFile(ArchiveFile(
        DatabaseConfig.databaseName,
        dbBytes.length,
        dbBytes,
      ));

      // Add WAL file if exists
      final walFile = File(walPath);
      if (await walFile.exists()) {
        _logging.debug('Adding WAL file to archive');
        final walBytes = await walFile.readAsBytes();
        archive.addFile(ArchiveFile(
          '${DatabaseConfig.databaseName}-wal',
          walBytes.length,
          walBytes,
        ));
      }

      // Add SHM file if exists
      final shmFile = File(shmPath);
      if (await shmFile.exists()) {
        _logging.debug('Adding SHM file to archive');
        final shmBytes = await shmFile.readAsBytes();
        archive.addFile(ArchiveFile(
          '${DatabaseConfig.databaseName}-shm',
          shmBytes.length,
          shmBytes,
        ));
      }

      // Encode and write archive
      _logging.debug('Writing backup archive');
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        return Err(const BackupException('Failed to create ZIP archive'));
      }

      await File(destinationPath).writeAsBytes(zipBytes);

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
      final dbPath = await DatabaseConfig.getDatabasePath();
      final dbDir = path.dirname(dbPath);

      // Close current database connection
      _logging.debug('Closing database connection');
      await DatabaseService.close();

      // Create backup of current files (safety measure)
      await _createTemporaryBackup(dbPath);

      try {
        // Extract files from archive
        _logging.debug('Extracting backup files');
        for (final file in archive) {
          if (file.isFile) {
            final targetPath = path.join(dbDir, file.name);
            final outputFile = File(targetPath);
            await outputFile.writeAsBytes(file.content as List<int>);
            _logging.debug('Extracted file', {'name': file.name});
          }
        }

        // Reinitialize database
        _logging.debug('Reinitializing database');
        await DatabaseService.initialize();
        await MigrationService.runMigrations();

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
          await DatabaseService.initialize();
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
  Future<void> _rollbackFromTemporaryBackup(String dbPath) async {
    final walPath = '$dbPath-wal';
    final shmPath = '$dbPath-shm';

    final dbBackup = File('$dbPath.bak');
    final walBackup = File('$walPath.bak');
    final shmBackup = File('$shmPath.bak');

    if (await dbBackup.exists()) {
      await dbBackup.copy(dbPath);
      await dbBackup.delete();
    }
    if (await walBackup.exists()) {
      await walBackup.copy(walPath);
      await walBackup.delete();
    }
    if (await shmBackup.exists()) {
      await shmBackup.copy(shmPath);
      await shmBackup.delete();
    }
  }
}
