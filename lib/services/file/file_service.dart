import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:twmt/config/database_config.dart';
import '../../models/common/result.dart';
import '../../models/common/service_exception.dart';

/// File service for managing application directories and file paths.
///
/// Provides methods to get and create application-specific directories
/// on Windows, following the AppData structure.
class FileService {
  FileService._();

  static final FileService _instance = FileService._();
  static FileService get instance => _instance;

  /// Get the database path.
  ///
  /// Returns: AppData\Roaming\TWMT\twmt.db
  /// In debug mode: AppData\Roaming\com.github.slavyk82\twmt\twmt.db
  Future<Result<String, FileSystemException>> getDatabasePath() async {
    try {
      final dbPath = await DatabaseConfig.getDatabasePath();
      return Ok(dbPath);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to get database path: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get the configuration directory.
  ///
  /// Returns: AppData\Roaming\TWMT\config
  /// In debug mode: AppData\Roaming\com.github.slavyk82\twmt\config
  /// Creates the directory if it doesn't exist.
  Future<Result<String, FileSystemException>> getConfigDirectory() async {
    try {
      final configPath = await DatabaseConfig.getConfigDirectory();
      return Ok(configPath);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to get config directory: $e',
          filePath: null,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get the logs directory.
  ///
  /// Returns: AppData\Local\TWMT\logs
  /// Creates the directory if it doesn't exist.
  Future<Result<String, FileSystemException>> getLogsDirectory() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final logsDir = Directory(path.join(dir.path, 'logs'));

      if (!await logsDir.exists()) {
        await logsDir.create(recursive: true);
      }

      return Ok(logsDir.path);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to get logs directory: $e',
          filePath: null,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get the cache directory.
  ///
  /// Returns: AppData\Local\TWMT\cache
  /// Creates the directory if it doesn't exist.
  Future<Result<String, FileSystemException>> getCacheDirectory() async {
    try {
      final dir = await getApplicationCacheDirectory();
      final cacheDir = Directory(path.join(dir.path, 'cache'));

      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      return Ok(cacheDir.path);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to get cache directory: $e',
          filePath: null,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get the application data directory root.
  ///
  /// Returns: AppData\Roaming\TWMT
  /// In debug mode: AppData\Roaming\com.github.slavyk82\twmt
  Future<Result<String, FileSystemException>> getAppDataDirectory() async {
    try {
      final appDir = await DatabaseConfig.getAppSupportDirectory();
      return Ok(appDir);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to get app data directory: $e',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Ensure a directory exists, creating it if necessary.
  ///
  /// Security: Validates path to prevent directory traversal attacks.
  Future<Result<void, FileSystemException>> ensureDirectoryExists(
    String directoryPath,
  ) async {
    try {
      // Validate path doesn't contain traversal sequences
      if (!_isValidPath(directoryPath)) {
        return Err(
          FileSystemException(
            'Invalid directory path: contains dangerous sequences',
            filePath: directoryPath,
          ),
        );
      }

      // Verify path is within app directory
      final isSafe = await _isPathSafe(directoryPath);
      if (!isSafe) {
        return Err(
          FileSystemException(
            'Access denied: path outside application directory',
            filePath: directoryPath,
          ),
        );
      }

      final dir = Directory(directoryPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return const Ok(null);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to create directory: $e',
          filePath: directoryPath,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Validate that a path exists and is accessible.
  Future<Result<bool, FileSystemException>> validatePath(String filePath) async {
    try {
      final entity = FileSystemEntity.typeSync(filePath);
      return Ok(entity != FileSystemEntityType.notFound);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to validate path: $e',
          filePath: filePath,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Get file size in bytes.
  Future<Result<int, FileSystemException>> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Err(
          FileSystemException(
            'File does not exist',
            filePath: filePath,
          ),
        );
      }
      final size = await file.length();
      return Ok(size);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to get file size: $e',
          filePath: filePath,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Delete a file.
  ///
  /// Security: Validates path to prevent unauthorized file deletion.
  Future<Result<void, FileSystemException>> deleteFile(String filePath) async {
    try {
      // Validate path doesn't contain traversal sequences
      if (!_isValidPath(filePath)) {
        return Err(
          FileSystemException(
            'Invalid file path: contains dangerous sequences',
            filePath: filePath,
          ),
        );
      }

      // Verify path is within app directory
      final isSafe = await _isPathSafe(filePath);
      if (!isSafe) {
        return Err(
          FileSystemException(
            'Access denied: path outside application directory',
            filePath: filePath,
          ),
        );
      }

      // Prevent deletion of critical files
      final fileName = path.basename(filePath).toLowerCase();
      if (_isCriticalFile(fileName)) {
        return Err(
          FileSystemException(
            'Access denied: cannot delete critical file',
            filePath: filePath,
          ),
        );
      }

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
      return const Ok(null);
    } catch (e, stackTrace) {
      return Err(
        FileSystemException(
          'Failed to delete file: $e',
          filePath: filePath,
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Validate path doesn't contain traversal sequences
  ///
  /// Checks for:
  /// - Directory traversal (.. sequences)
  /// - Null bytes (\0)
  /// - Empty or whitespace-only paths
  bool _isValidPath(String filePath) {
    if (filePath.trim().isEmpty) {
      return false;
    }

    // Check for directory traversal
    if (filePath.contains('..')) {
      return false;
    }

    // Check for null bytes (can truncate paths in some systems)
    if (filePath.contains('\u0000')) {
      return false;
    }

    return true;
  }

  /// Verify path is within application directory
  ///
  /// Resolves the canonical path and ensures it starts with the
  /// application's data directory. This prevents access to files
  /// outside the application's sandbox.
  Future<bool> _isPathSafe(String targetPath) async {
    try {
      // Get application directory
      final appDirPath = await DatabaseConfig.getAppSupportDirectory();
      final canonicalAppDir = Directory(appDirPath).absolute.path;

      // Resolve target path (follows symlinks)
      final absoluteTarget = path.isAbsolute(targetPath)
          ? targetPath
          : path.join(Directory.current.path, targetPath);

      // Normalize path separators for Windows
      final normalizedTarget = absoluteTarget.replaceAll('/', '\\');
      final normalizedAppDir = canonicalAppDir.replaceAll('/', '\\');

      // Check if target is within app directory
      return normalizedTarget.startsWith(normalizedAppDir);
    } catch (e) {
      // If we can't resolve, reject for safety
      return false;
    }
  }

  /// Check if file is critical and should not be deleted
  ///
  /// Critical files include:
  /// - Database file (twmt.db)
  /// - Configuration files
  /// - Environment variables
  bool _isCriticalFile(String fileName) {
    const criticalFiles = [
      'twmt.db',          // Main database
      'twmt.db-shm',      // SQLite shared memory
      'twmt.db-wal',      // SQLite write-ahead log
      'config.json',      // Configuration
      '.env',             // Environment variables
      'settings.json',    // User settings
    ];

    return criticalFiles.contains(fileName);
  }
}
