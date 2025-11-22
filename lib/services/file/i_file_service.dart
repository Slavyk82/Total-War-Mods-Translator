import 'package:twmt/models/common/result.dart';
import 'models/file_exceptions.dart';

/// Interface for file system operations
///
/// Provides abstraction over file I/O with:
/// - Path management (AppData, temp dirs)
/// - File watching for external changes
/// - Import/Export workflows (CSV, JSON, Excel)
/// - Temporary file cleanup
/// - Safe file operations with error handling
abstract class IFileService {
  /// Read file content as string
  ///
  /// [filePath]: Absolute path to file
  /// [encoding]: File encoding (default: utf-8)
  ///
  /// Returns file content
  ///
  /// Throws:
  /// - FileNotFoundException if file doesn't exist
  /// - FileAccessDeniedException if no read permission
  /// - FileEncodingException if encoding is invalid
  Future<Result<String, FileServiceException>> readFile({
    required String filePath,
    String encoding = 'utf-8',
  });

  /// Read file content as bytes
  ///
  /// [filePath]: Absolute path to file
  ///
  /// Returns file bytes
  Future<Result<List<int>, FileServiceException>> readFileBytes({
    required String filePath,
  });

  /// Write string content to file
  ///
  /// [filePath]: Absolute path to file
  /// [content]: String content to write
  /// [encoding]: File encoding (default: utf-8)
  /// [createDirectories]: Create parent directories if they don't exist
  ///
  /// Returns path to written file
  ///
  /// Throws:
  /// - FileWriteException if writing fails
  /// - FileAccessDeniedException if no write permission
  Future<Result<String, FileServiceException>> writeFile({
    required String filePath,
    required String content,
    String encoding = 'utf-8',
    bool createDirectories = true,
  });

  /// Write bytes to file
  ///
  /// [filePath]: Absolute path to file
  /// [bytes]: Bytes to write
  /// [createDirectories]: Create parent directories if they don't exist
  ///
  /// Returns path to written file
  Future<Result<String, FileServiceException>> writeFileBytes({
    required String filePath,
    required List<int> bytes,
    bool createDirectories = true,
  });

  /// Delete file
  ///
  /// [filePath]: Absolute path to file
  ///
  /// Returns true if deleted successfully
  ///
  /// Throws:
  /// - FileNotFoundException if file doesn't exist
  /// - FileAccessDeniedException if no delete permission
  Future<Result<bool, FileServiceException>> deleteFile({
    required String filePath,
  });

  /// Copy file
  ///
  /// [sourcePath]: Source file path
  /// [destinationPath]: Destination file path
  /// [overwrite]: Whether to overwrite if destination exists
  ///
  /// Returns path to copied file
  Future<Result<String, FileServiceException>> copyFile({
    required String sourcePath,
    required String destinationPath,
    bool overwrite = false,
  });

  /// Move/rename file
  ///
  /// [sourcePath]: Source file path
  /// [destinationPath]: Destination file path
  /// [overwrite]: Whether to overwrite if destination exists
  ///
  /// Returns path to moved file
  Future<Result<String, FileServiceException>> moveFile({
    required String sourcePath,
    required String destinationPath,
    bool overwrite = false,
  });

  /// Check if file exists
  ///
  /// [filePath]: Path to check
  ///
  /// Returns true if file exists
  Future<bool> fileExists(String filePath);

  /// Get file metadata
  ///
  /// [filePath]: Path to file
  ///
  /// Returns FileInfo with size, modified date, etc.
  Future<Result<FileInfo, FileServiceException>> getFileInfo({
    required String filePath,
  });

  /// List files in directory
  ///
  /// [directoryPath]: Path to directory
  /// [pattern]: Optional glob pattern to filter files
  /// [recursive]: Whether to list files recursively
  ///
  /// Returns list of file paths
  Future<Result<List<String>, FileServiceException>> listFiles({
    required String directoryPath,
    String? pattern,
    bool recursive = false,
  });

  /// Create directory
  ///
  /// [directoryPath]: Path to directory
  /// [recursive]: Create parent directories if they don't exist
  ///
  /// Returns path to created directory
  Future<Result<String, FileServiceException>> createDirectory({
    required String directoryPath,
    bool recursive = true,
  });

  /// Delete directory
  ///
  /// [directoryPath]: Path to directory
  /// [recursive]: Delete directory and all contents
  ///
  /// Returns true if deleted successfully
  Future<Result<bool, FileServiceException>> deleteDirectory({
    required String directoryPath,
    bool recursive = false,
  });

  /// Get application data directory
  ///
  /// Returns path to AppData\Roaming\TWMT on Windows
  Future<String> getAppDataDirectory();

  /// Get application config directory
  ///
  /// Returns path to AppData\Roaming\TWMT\config
  Future<String> getConfigDirectory();

  /// Get application database directory
  ///
  /// Returns path to AppData\Roaming\TWMT (database location)
  Future<String> getDatabaseDirectory();

  /// Get application logs directory
  ///
  /// Returns path to AppData\Local\TWMT\logs
  Future<String> getLogsDirectory();

  /// Get application cache directory
  ///
  /// Returns path to AppData\Local\TWMT\cache
  Future<String> getCacheDirectory();

  /// Get temporary directory
  ///
  /// Returns path to system temp directory
  Future<String> getTempDirectory();

  /// Create temporary file
  ///
  /// [prefix]: Optional prefix for temp file name
  /// [suffix]: Optional suffix for temp file name
  ///
  /// Returns path to created temp file
  Future<Result<String, FileServiceException>> createTempFile({
    String? prefix,
    String? suffix,
  });

  /// Cleanup old temporary files
  ///
  /// [olderThan]: Delete files older than this duration
  ///
  /// Returns number of files deleted
  Future<Result<int, FileServiceException>> cleanupTempFiles({
    Duration olderThan = const Duration(days: 7),
  });

  /// Watch file or directory for changes
  ///
  /// [path]: Path to watch
  ///
  /// Returns stream of FileChangeEvent
  ///
  /// Events:
  /// - FileChangeType.created: New file created
  /// - FileChangeType.modified: File content changed
  /// - FileChangeType.deleted: File deleted
  /// - FileChangeType.moved: File moved/renamed
  Stream<FileChangeEvent> watchFile({
    required String path,
  });

  /// Stop watching a path
  ///
  /// [path]: Path to stop watching
  Future<void> stopWatching({
    required String path,
  });

  /// Import data from CSV file
  ///
  /// [filePath]: Path to CSV file
  /// [hasHeader]: Whether first row is header
  ///
  /// Returns list of rows (each row is a map of column name → value)
  Future<Result<List<Map<String, String>>, ImportException>> importFromCsv({
    required String filePath,
    bool hasHeader = true,
  });

  /// Export data to CSV file
  ///
  /// [data]: Data to export (list of maps)
  /// [filePath]: Destination CSV file path
  /// [headers]: Column headers (if null, use keys from first row)
  ///
  /// Returns path to exported file
  Future<Result<String, ExportException>> exportToCsv({
    required List<Map<String, String>> data,
    required String filePath,
    List<String>? headers,
  });

  /// Import data from JSON file
  ///
  /// [filePath]: Path to JSON file
  ///
  /// Returns parsed JSON data
  Future<Result<dynamic, ImportException>> importFromJson({
    required String filePath,
  });

  /// Export data to JSON file
  ///
  /// [data]: Data to export
  /// [filePath]: Destination JSON file path
  /// [prettyPrint]: Whether to format JSON with indentation
  ///
  /// Returns path to exported file
  Future<Result<String, ExportException>> exportToJson({
    required dynamic data,
    required String filePath,
    bool prettyPrint = true,
  });

  /// Import data from Excel file (.xlsx)
  ///
  /// [filePath]: Path to Excel file
  /// [sheetName]: Sheet name to import (default: first sheet)
  /// [hasHeader]: Whether first row is header
  ///
  /// Returns list of rows
  Future<Result<List<Map<String, String>>, ImportException>> importFromExcel({
    required String filePath,
    String? sheetName,
    bool hasHeader = true,
  });

  /// Export data to Excel file (.xlsx)
  ///
  /// [data]: Data to export
  /// [filePath]: Destination Excel file path
  /// [sheetName]: Sheet name (default: "Sheet1")
  /// [headers]: Column headers
  ///
  /// Returns path to exported file
  Future<Result<String, ExportException>> exportToExcel({
    required List<Map<String, String>> data,
    required String filePath,
    String sheetName = 'Sheet1',
    List<String>? headers,
  });

  /// Calculate file hash (for change detection)
  ///
  /// [filePath]: Path to file
  /// [algorithm]: Hash algorithm - 'sha256' (default), 'sha1', 'sha224',
  ///              'sha384', 'sha512', or 'md5'
  ///
  /// Returns hex-encoded hash string
  ///
  /// Example:
  /// ```dart
  /// final result = await fileService.calculateFileHash(
  ///   filePath: 'path/to/file.txt',
  ///   algorithm: 'sha256',
  /// );
  /// result.fold(
  ///   ok: (hash) => print('Hash: $hash'),
  ///   err: (error) => print('Error: $error'),
  /// );
  /// ```
  Future<Result<String, FileServiceException>> calculateFileHash({
    required String filePath,
    String algorithm = 'sha256',
  });

  /// Compare two files
  ///
  /// [filePath1]: First file path
  /// [filePath2]: Second file path
  /// [compareContent]: Whether to compare content (vs just metadata)
  ///
  /// Returns true if files are identical
  Future<Result<bool, FileServiceException>> compareFiles({
    required String filePath1,
    required String filePath2,
    bool compareContent = true,
  });
}

/// File metadata information
class FileInfo {
  /// File path
  final String path;

  /// File name (without path)
  final String name;

  /// File size in bytes
  final int sizeBytes;

  /// When file was created
  final DateTime createdAt;

  /// When file was last modified
  final DateTime modifiedAt;

  /// When file was last accessed
  final DateTime? accessedAt;

  /// Whether file is read-only
  final bool isReadOnly;

  /// File extension (e.g., '.loc', '.json')
  final String? extension;

  const FileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.createdAt,
    required this.modifiedAt,
    this.accessedAt,
    this.isReadOnly = false,
    this.extension,
  });

  /// File size in human-readable format
  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  String toString() {
    return 'FileInfo(name: $name, size: $sizeFormatted, modified: $modifiedAt)';
  }
}

/// File change event (for file watching)
class FileChangeEvent {
  /// Type of change
  final FileChangeType type;

  /// Path to file that changed
  final String path;

  /// When change occurred
  final DateTime timestamp;

  /// Old path (for move events)
  final String? oldPath;

  const FileChangeEvent({
    required this.type,
    required this.path,
    required this.timestamp,
    this.oldPath,
  });

  @override
  String toString() {
    return 'FileChangeEvent(type: $type, path: $path, timestamp: $timestamp)';
  }
}

/// Type of file change
enum FileChangeType {
  /// File was created
  created,

  /// File content was modified
  modified,

  /// File was deleted
  deleted,

  /// File was moved or renamed
  moved,
}
