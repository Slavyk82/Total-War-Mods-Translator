import 'dart:io';
import 'package:archive/archive_io.dart';
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
///
/// Both directions are streamed: archive entries flow file→file through
/// fixed-size stream buffers, so peak memory stays a few megabytes even for
/// multi-gigabyte databases (a 2 GB database must never be materialized in
/// memory during backup or restore).
///
/// NOTE on Windows path length: backup/restore work with user-chosen paths
/// plus short suffixes ('.tmp', '.restore-tmp', '.bak'). Paths longer than
/// MAX_PATH (260 chars) are not special-cased with a '\\?\' prefix here;
/// such paths fail with a clear filesystem error instead.
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

  /// The only archive entry names a TWMT backup may contain. Anything else
  /// (in particular relative `..` or absolute paths smuggled into a
  /// user-supplied ZIP) is rejected during validation and skipped during
  /// extraction, so an archive entry can never escape the database directory.
  static final Set<String> _allowedEntryNames = {
    DatabaseConfig.databaseName,
    '${DatabaseConfig.databaseName}-wal',
    '${DatabaseConfig.databaseName}-shm',
  };

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

    Directory? workDir;
    final tempZipPath = '$destinationPath.tmp';
    var tempZipNeedsCleanup = false;
    OutputFileStream? zipOutput;

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

      // Scratch directory for the VACUUM INTO snapshot and the per-entry
      // deflate temp files used by the streamed archive writer.
      workDir = await Directory.systemTemp.createTemp('twmt_backup_');

      final useVacuumInto = DatabaseService.isInitialized &&
          !debugForceLegacySnapshot &&
          await _isVacuumIntoSupported();

      // (entry name, source file path) pairs to stream into the archive.
      final sources = <(String, String)>[];
      if (useVacuumInto) {
        // VACUUM INTO runs as a single read transaction on the connection's
        // statement queue, so the snapshot is consistent regardless of
        // concurrent writers and never pairs a stale main file with a
        // mismatched WAL.
        final snapshotPath =
            path.join(workDir.path, DatabaseConfig.databaseName);
        _logging.debug('Creating consistent snapshot via VACUUM INTO');
        await DatabaseService.database
            .execute('VACUUM INTO ?', [snapshotPath]);
        sources.add((DatabaseConfig.databaseName, snapshotPath));
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
        _logging.debug('Adding database file to archive');
        sources.add((DatabaseConfig.databaseName, dbPath));
        for (final suffix in const ['-wal', '-shm']) {
          final sidecarPath = '$dbPath$suffix';
          if (await File(sidecarPath).exists()) {
            _logging.debug('Adding sidecar file to archive', {
              'suffix': suffix,
            });
            sources.add(('${DatabaseConfig.databaseName}$suffix', sidecarPath));
          }
        }
      }

      // Stream the archive straight to the temp zip file and rename it over
      // the final name, so an interrupted backup never leaves a half-written
      // file that looks like a valid archive. Each entry is compressed
      // file→file and copied into the zip in chunks: peak memory stays a few
      // stream buffers instead of the full database size.
      _logging.debug('Writing backup archive');
      tempZipNeedsCleanup = true;
      zipOutput = OutputFileStream(tempZipPath);
      final encoder = ZipEncoder();
      encoder.startEncode(zipOutput);
      var entryIndex = 0;
      for (final (entryName, sourcePath) in sources) {
        final deflateTempPath =
            path.join(workDir.path, 'entry-${entryIndex++}.deflate');
        await _addFileToZipStreamed(
          encoder,
          entryName,
          sourcePath,
          deflateTempPath,
        );
      }
      encoder.endEncode();
      await zipOutput.close();
      zipOutput = null;

      await File(tempZipPath).rename(destinationPath);
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
      // Close the zip output before deleting the temp file: an open handle
      // keeps the file locked on Windows.
      if (zipOutput != null) {
        try {
          zipOutput.closeSync();
        } catch (e) {
          _logging.warning('Failed to close backup archive stream', {
            'path': tempZipPath,
            'error': e.toString(),
          });
        }
      }
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
      if (workDir != null) {
        try {
          await workDir.delete(recursive: true);
        } catch (e) {
          _logging.warning('Failed to delete snapshot directory', {
            'path': workDir.path,
            'error': e.toString(),
          });
        }
      }
    }
  }

  /// Add the file at [sourcePath] to [encoder] as [entryName] without ever
  /// materializing it in memory.
  ///
  /// The file is first deflate-compressed file→file into [deflateTempPath]:
  /// [Deflate.buffer] reads the input and writes the compressed output
  /// through fixed-size stream buffers and keeps a running CRC-32 of the
  /// uncompressed input as a side effect. The pre-compressed bytes are then
  /// handed to [ZipEncoder.addFile] as an already-deflated entry, which the
  /// encoder copies into the archive in 1 MB chunks. (ZipFileEncoder.addFile
  /// in archive 3.x is NOT used because it buffers both the whole
  /// uncompressed file and its deflated form in memory.)
  ///
  /// [Deflate.BEST_SPEED] matches the compression level the previous
  /// in-memory `ZipEncoder().encode` implementation used, so produced
  /// archives stay byte-compatible with the validate/restore path.
  Future<void> _addFileToZipStreamed(
    ZipEncoder encoder,
    String entryName,
    String sourcePath,
    String deflateTempPath,
  ) async {
    final sourceLength = await File(sourcePath).length();

    var crc32 = 0;
    final input = InputFileStream(sourcePath);
    try {
      final deflateOutput = OutputFileStream(deflateTempPath);
      try {
        final deflate = Deflate.buffer(
          input,
          level: Deflate.BEST_SPEED,
          output: deflateOutput,
        );
        deflate.finish();
        crc32 = deflate.crc32;
      } finally {
        await deflateOutput.close();
      }
    } finally {
      await input.close();
    }

    final compressedInput = InputFileStream(deflateTempPath);
    try {
      final entry = ArchiveFile(
        entryName,
        sourceLength,
        compressedInput,
        ArchiveFile.DEFLATE,
      )
        ..crc32 = crc32
        // The constructor falls back to the COMPRESSED stream length when
        // size <= 0; force the real uncompressed size so zero-byte sources
        // (e.g. a TRUNCATE-checkpointed WAL) carry correct zip metadata.
        ..size = sourceLength;
      // addFile streams the pre-compressed bytes into the zip output and
      // closes [compressedInput] (autoClose defaults to true).
      encoder.addFile(entry);
    } finally {
      // Idempotent when addFile already closed the stream; required when
      // addFile threw before closing it (Windows file locks).
      compressedInput.closeSync();
    }
    await File(deflateTempPath).delete();
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

  /// Check every entry of [archive] against [_allowedEntryNames] and report
  /// which of the expected files are present.
  ///
  /// Returns a non-null `error` for the first unexpected entry (zip-slip /
  /// path-traversal hardening). Only entry NAMES are inspected here: the
  /// allowlist verdict is reached before a single entry byte is decompressed
  /// or written anywhere, which matters for lazily-decoded archives.
  ({
    BackupException? error,
    bool hasWalFile,
    bool hasShmFile,
    ArchiveFile? dbEntry,
  }) _inspectArchiveEntries(Archive archive) {
    var hasWalFile = false;
    var hasShmFile = false;
    ArchiveFile? dbEntry;

    for (final file in archive) {
      if (!_allowedEntryNames.contains(file.name)) {
        return (
          error: BackupException(
            'Invalid backup: unexpected archive entry "${file.name}". '
            'A TWMT backup may only contain ${DatabaseConfig.databaseName} '
            'and its -wal/-shm sidecar files.',
          ),
          hasWalFile: false,
          hasShmFile: false,
          dbEntry: null,
        );
      }
      if (file.name == DatabaseConfig.databaseName) {
        dbEntry ??= file;
      } else if (file.name == '${DatabaseConfig.databaseName}-wal') {
        hasWalFile = true;
      } else if (file.name == '${DatabaseConfig.databaseName}-shm') {
        hasShmFile = true;
      }
    }

    return (
      error: null,
      hasWalFile: hasWalFile,
      hasShmFile: hasShmFile,
      dbEntry: dbEntry,
    );
  }

  /// Stream-extract a single archive [entry] to [outputPath].
  ///
  /// The bytes flow compressed-file → inflater → output-file through
  /// fixed-size buffers: [ArchiveFile.decompress] uses `Inflate.stream` for
  /// deflate entries and a 1 MB chunked copy for stored entries, so the
  /// entry is never materialized in memory. [ArchiveFile.clear] drops the
  /// lazily-decoded content reference first so `decompress` takes the
  /// streaming path; the entry can therefore only be extracted once.
  Future<void> _extractEntryToFile(ArchiveFile entry, String outputPath) async {
    final output = OutputFileStream(outputPath);
    try {
      entry.clear();
      entry.decompress(output);
    } finally {
      // Always release the handle: an open stream keeps the file locked on
      // Windows and would break temp-file cleanup.
      await output.close();
    }
  }

  /// Read the first 100 bytes of [filePath] and validate them as a SQLite
  /// header via [_validateDatabaseHeader].
  Future<BackupException?> _validateDatabaseHeaderFromFile(
    String filePath,
  ) async {
    final raf = await File(filePath).open();
    try {
      final bytes = await raf.read(100);
      return _validateDatabaseHeader(bytes);
    } finally {
      await raf.close();
    }
  }

  /// Validate a backup file without restoring it.
  ///
  /// Returns information about the backup contents.
  ///
  /// The archive is decoded from a file stream (only the central directory
  /// is parsed up front). Header validation needs the first 100
  /// *uncompressed* bytes of the twmt.db entry, which requires inflating the
  /// entry: it is stream-extracted to a probe file in the system temp
  /// directory and the header is read back from that file, keeping memory
  /// bounded regardless of database size.
  Future<Result<BackupInfo, BackupException>> validateBackup(
    String zipPath,
  ) async {
    _logging.debug('Validating backup', {'path': zipPath});

    InputFileStream? archiveInput;
    Directory? probeDir;
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return Err(const BackupException('Backup file not found'));
      }

      final fileSize = await zipFile.length();
      archiveInput = InputFileStream(zipPath);

      final Archive archive;
      try {
        archive = ZipDecoder().decodeBuffer(archiveInput);
      } catch (e) {
        return Err(BackupException('Invalid ZIP file: $e'));
      }

      // Entry-name allowlist BEFORE any entry bytes are touched.
      final entries = _inspectArchiveEntries(archive);
      if (entries.error != null) {
        return Err(entries.error!);
      }

      final info = BackupInfo(
        filePath: zipPath,
        fileSize: fileSize,
        hasDatabaseFile: entries.dbEntry != null,
        hasWalFile: entries.hasWalFile,
        hasShmFile: entries.hasShmFile,
      );

      if (!info.isValid) {
        return Err(const BackupException(
          'Invalid backup: missing database file (twmt.db)',
        ));
      }

      // Guard against restoring an uninitialized or incompatible database:
      // a twmt.db with user_version 0 would be treated as a fresh database by
      // MigrationService after restore (schema.sql silently re-run over it),
      // replacing the user's data with an empty database.
      probeDir = await Directory.systemTemp.createTemp('twmt_validate_');
      final probePath = path.join(probeDir.path, DatabaseConfig.databaseName);
      await _extractEntryToFile(entries.dbEntry!, probePath);
      final databaseError = await _validateDatabaseHeaderFromFile(probePath);
      if (databaseError != null) {
        return Err(databaseError);
      }

      _logging.debug('Backup validated successfully', {
        'hasDatabaseFile': info.hasDatabaseFile,
        'hasWalFile': info.hasWalFile,
        'hasShmFile': info.hasShmFile,
      });

      return Ok(info);
    } catch (e, stackTrace) {
      _logging.error('Failed to validate backup', e, stackTrace);
      return Err(BackupException(
        'Failed to validate backup: $e',
        error: e,
        stackTrace: stackTrace,
      ));
    } finally {
      // Close the archive stream first: open handles keep files locked on
      // Windows and would block the probe-directory deletion below.
      if (archiveInput != null) {
        try {
          await archiveInput.close();
        } catch (e) {
          _logging.warning('Failed to close backup archive stream', {
            'path': zipPath,
            'error': e.toString(),
          });
        }
      }
      if (probeDir != null) {
        try {
          await probeDir.delete(recursive: true);
        } catch (e) {
          _logging.warning('Failed to delete validation probe directory', {
            'path': probeDir.path,
            'error': e.toString(),
          });
        }
      }
    }
  }

  /// Validate the SQLite header of a backup's database file.
  ///
  /// Checks the 16-byte magic string and reads `user_version` directly from
  /// the header (offset 60, big-endian 32-bit) without handing untrusted
  /// bytes to the SQLite engine. Returns `null` when the database looks
  /// restorable, otherwise the [BackupException] describing the rejection.
  ///
  /// Backups created by TWMT always carry the schema version in the main
  /// file header: `VACUUM INTO` snapshots are self-contained, and the legacy
  /// file-copy path checkpoints the WAL before copying.
  BackupException? _validateDatabaseHeader(List<int> bytes) {
    // A valid SQLite database starts with a fixed 100-byte header.
    const headerSize = 100;
    const magic = 'SQLite format 3';
    if (bytes.length < headerSize) {
      return const BackupException(
        'Invalid backup: the database file is not a valid SQLite database '
        '(file is smaller than the SQLite header)',
      );
    }
    for (var i = 0; i < magic.length; i++) {
      if (bytes[i] != magic.codeUnitAt(i)) {
        return const BackupException(
          'Invalid backup: the database file is not a valid SQLite database',
        );
      }
    }
    if (bytes[15] != 0x00) {
      return const BackupException(
        'Invalid backup: the database file is not a valid SQLite database',
      );
    }

    // user_version lives at header offset 60 as a big-endian 32-bit integer.
    final userVersion =
        (bytes[60] << 24) | (bytes[61] << 16) | (bytes[62] << 8) | bytes[63];
    if (userVersion == 0) {
      return const BackupException(
        'Invalid backup: the database has no schema version (user_version '
        'is 0). Restoring it would replace your data with an empty database.',
      );
    }
    if (userVersion > DatabaseConfig.databaseVersion) {
      return BackupException(
        'Invalid backup: the database schema version ($userVersion) is newer '
        'than this application supports '
        '(${DatabaseConfig.databaseVersion}). Please update the application '
        'before restoring this backup.',
      );
    }
    return null;
  }

  /// Restore the database from a backup.
  ///
  /// WARNING: This will replace the current database.
  /// The application may need to be restarted after restore.
  ///
  /// Restore flow (restructured for streamed decoding):
  ///
  ///  1. Decode the archive from a file stream and check the entry-name
  ///     allowlist BEFORE a single entry byte is read (zip-slip protection).
  ///  2. Stream-extract twmt.db to `twmt.db.restore-tmp` next to the target
  ///     and validate its SQLite header from that file. With a streamed
  ///     decode the header bytes only exist after inflating the entry, so
  ///     the temp file doubles as validation source; any rejection happens
  ///     here, before the live database is closed or touched.
  ///  3. Close the database and create verified `.bak` safety copies.
  ///  4. Stream-extract the optional -wal/-shm entries to their own
  ///     `.restore-tmp` files, then atomically rename every temp file over
  ///     its target (same directory, hence same volume): a crash mid-write
  ///     can truncate only a temp file, never the database itself.
  ///  5. Remove stale sidecars, reinitialize, drop the `.bak` files.
  Future<Result<void, BackupException>> restoreBackup(String zipPath) async {
    _logging.info('Restoring database from backup', {'source': zipPath});

    InputFileStream? archiveInput;
    // Path of the pre-extracted twmt.db.restore-tmp file; non-null until it
    // has been renamed into place so every failure path can clean it up.
    String? pendingDbTempPath;
    try {
      final zipFile = File(zipPath);
      if (!await zipFile.exists()) {
        return Err(const BackupException('Backup file not found'));
      }

      // Get database directory
      final dbPath = await _getDatabasePath();
      final dbDir = path.dirname(dbPath);

      archiveInput = InputFileStream(zipPath);
      final Archive archive;
      try {
        archive = ZipDecoder().decodeBuffer(archiveInput);
      } catch (e) {
        return Err(BackupException('Invalid ZIP file: $e'));
      }

      // Step 1: entry-name allowlist before any bytes are written anywhere.
      final entries = _inspectArchiveEntries(archive);
      if (entries.error != null) {
        return Err(entries.error!);
      }
      final dbEntry = entries.dbEntry;
      if (dbEntry == null) {
        return Err(const BackupException(
          'Invalid backup: missing database file (twmt.db)',
        ));
      }

      // Step 2: extract and header-validate the database entry while the
      // current database is still untouched and open.
      _logging.debug('Extracting database file from backup');
      final dbTargetPath = path.join(dbDir, DatabaseConfig.databaseName);
      final dbTempPath = '$dbTargetPath.restore-tmp';
      pendingDbTempPath = dbTempPath;
      await _extractEntryToFile(dbEntry, dbTempPath);
      final databaseError = await _validateDatabaseHeaderFromFile(dbTempPath);
      if (databaseError != null) {
        return Err(databaseError);
      }

      // Close current database connection
      _logging.debug('Closing database connection');
      await _closeDatabase();

      // Create backup of current files (safety measure). The database is
      // already closed here, so a failure in this step must reinitialize the
      // database itself: letting it propagate to the outer catch would leave
      // the app with a silently closed database.
      try {
        await _createTemporaryBackup(dbPath);
      } catch (e, stackTrace) {
        _logging.error(
            'Failed to create safety backup before restore', e, stackTrace);
        await _cleanupTemporaryBackupBestEffort(dbPath);
        try {
          await _reinitializeDatabase();
        } catch (_) {
          return Err(BackupException(
            'Failed to create safety backup before restore and the database '
            'could not be reinitialized. Please restart the application.',
            requiresRestart: true,
            error: e,
            stackTrace: stackTrace,
          ));
        }
        return Err(BackupException(
          'Failed to create safety backup before restore: $e',
          error: e,
          stackTrace: stackTrace,
        ));
      }

      try {
        // Step 4: stream-extract the remaining (sidecar) entries to their
        // .restore-tmp files. The database entry was already extracted in
        // step 2.
        _logging.debug('Extracting backup files');
        final extractedNames = <String>{DatabaseConfig.databaseName};
        final tempByTarget = <String, String>{dbTargetPath: dbTempPath};
        for (final file in archive) {
          if (!file.isFile) continue;
          if (file.name == DatabaseConfig.databaseName) continue;
          if (!_allowedEntryNames.contains(file.name)) {
            // Defense in depth: the allowlist above already rejects archives
            // with unexpected entries, but never let an untrusted entry name
            // (e.g. "..\\evil" or an absolute path) reach the filesystem.
            _logging.warning('Skipping unexpected archive entry during restore', {
              'name': file.name,
            });
            continue;
          }
          final targetPath = path.join(dbDir, file.name);
          final tempPath = '$targetPath.restore-tmp';
          await _extractEntryToFile(file, tempPath);
          tempByTarget[targetPath] = tempPath;
          extractedNames.add(file.name);
          _logging.debug('Extracted file', {'name': file.name});
        }

        // Atomically rename every extracted temp file over its target (same
        // directory, hence same volume): a crash mid-write can truncate only
        // a temp file, never the database file itself.
        for (final extracted in tempByTarget.entries) {
          await File(extracted.value).rename(extracted.key);
        }
        pendingDbTempPath = null;

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

        // Remove any half-written extraction temp file, then restore from
        // the temporary backup.
        await _cleanupRestoreTempFiles(dbDir);
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
    } finally {
      // Release the archive handle before deleting temp files: an open
      // stream keeps files locked on Windows.
      if (archiveInput != null) {
        try {
          await archiveInput.close();
        } catch (e) {
          _logging.warning('Failed to close backup archive stream', {
            'path': zipPath,
            'error': e.toString(),
          });
        }
      }
      // Remove the pre-extracted database temp file on any path that did
      // not rename it into place (validation rejection, safety-backup
      // failure, ...). The rollback path may have deleted it already.
      if (pendingDbTempPath != null) {
        try {
          final tempFile = File(pendingDbTempPath);
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (e) {
          _logging.warning('Failed to delete extraction temp file', {
            'path': pendingDbTempPath,
            'error': e.toString(),
          });
        }
      }
    }
  }

  /// Create a temporary backup of current database files.
  ///
  /// Every `.bak` copy is verified against the source file's length before
  /// the restore is allowed to proceed: a truncated safety copy must fail
  /// the restore up front instead of being discovered during a rollback.
  Future<void> _createTemporaryBackup(String dbPath) async {
    for (final sourcePath in [dbPath, '$dbPath-wal', '$dbPath-shm']) {
      final sourceFile = File(sourcePath);
      if (await sourceFile.exists()) {
        final backupPath = '$sourcePath.bak';
        await sourceFile.copy(backupPath);
        await verifyBackupCopy(sourcePath, backupPath);
      }
    }
  }

  /// Verify that the safety copy at [backupPath] has the same length as the
  /// source file at [sourcePath].
  ///
  /// Throws a [BackupException] on mismatch so the restore aborts before the
  /// original files are overwritten.
  @visibleForTesting
  static Future<void> verifyBackupCopy(
    String sourcePath,
    String backupPath,
  ) async {
    final sourceLength = await File(sourcePath).length();
    final backupLength = await File(backupPath).length();
    if (sourceLength != backupLength) {
      throw BackupException(
        'Safety backup verification failed: copy of "$sourcePath" has '
        '$backupLength bytes, expected $sourceLength bytes',
      );
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

  /// Best-effort variant of [_cleanupTemporaryBackup]: a cleanup failure
  /// must never mask the error that triggered the cleanup.
  Future<void> _cleanupTemporaryBackupBestEffort(String dbPath) async {
    try {
      await _cleanupTemporaryBackup(dbPath);
    } catch (e) {
      _logging.warning('Failed to clean up partial safety backup files', {
        'dbPath': dbPath,
        'error': e.toString(),
      });
    }
  }

  /// Best-effort removal of half-written `.restore-tmp` extraction files
  /// left behind by a failed restore.
  Future<void> _cleanupRestoreTempFiles(String dbDir) async {
    for (final name in _allowedEntryNames) {
      try {
        final tempFile = File(path.join(dbDir, '$name.restore-tmp'));
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        _logging.warning('Failed to delete extraction temp file', {
          'name': name,
          'error': e.toString(),
        });
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
