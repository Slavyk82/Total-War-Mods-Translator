import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:watcher/watcher.dart';
import 'package:twmt/config/database_config.dart';
import 'package:twmt/models/common/result.dart';
import 'package:twmt/services/file/i_file_service.dart';
import 'package:twmt/services/file/models/file_exceptions.dart';

/// Service for file watching and temporary file management
///
/// Handles file system watching for changes and automatic cleanup
/// of temporary files.
///
/// This service is used internally by FileServiceImpl to provide
/// file watching capabilities while keeping file sizes manageable.
class FileWatchService {
  /// Singleton instance
  static final FileWatchService _instance = FileWatchService._internal();

  factory FileWatchService() => _instance;

  FileWatchService._internal();

  /// Active file watchers (path -> watcher data)
  final Map<String, _WatcherData> _watchers = {};

  /// Tracked temporary files for auto-deletion
  final Set<String> _trackedTempFiles = {};

  // ============================================================================
  // FILE WATCHING OPERATIONS
  // ============================================================================

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
  ///
  /// Implementation uses the `watcher` package for cross-platform file watching.
  /// The stream will automatically close when stopWatching is called or when
  /// the stream is cancelled.
  ///
  /// Example:
  /// ```dart
  /// final stream = fileService.watchFile(path: 'path/to/file.pack');
  /// await for (final event in stream) {
  ///   print('File ${event.type}: ${event.path}');
  /// }
  /// ```
  Stream<FileChangeEvent> watchFile({
    required String path,
  }) async* {
    // Normalize the path
    final normalizedPath = path.replaceAll('\\', '/');

    // Check if already watching this path
    if (_watchers.containsKey(normalizedPath)) {
      // Return existing stream
      yield* _watchers[normalizedPath]!.controller.stream;
      return;
    }

    // Check if path exists
    final entity = FileSystemEntity.typeSync(normalizedPath);
    if (entity == FileSystemEntityType.notFound) {
      throw FileWatchException(
        'Cannot watch non-existent path: $normalizedPath',
        normalizedPath,
      );
    }

    // Create stream controller for this watcher
    final controller = StreamController<FileChangeEvent>.broadcast(
      onCancel: () async {
        // Clean up when last listener cancels
        await stopWatching(path: normalizedPath);
      },
    );

    try {
      // Determine if we're watching a file or directory
      final isDirectory = entity == FileSystemEntityType.directory;

      // Create appropriate watcher
      // Note: For files, we watch the parent directory and filter events
      final Watcher watcher;
      final String watchPath;
      final String? filterPath;

      if (isDirectory) {
        watcher = DirectoryWatcher(normalizedPath);
        watchPath = normalizedPath;
        filterPath = null;
      } else {
        // Watch the parent directory for file changes
        final file = File(normalizedPath);
        watchPath = file.parent.path;
        filterPath = normalizedPath;
        watcher = DirectoryWatcher(watchPath);
      }

      // Listen to watcher events and convert to FileChangeEvent
      final subscription = watcher.events.listen(
        (event) {
          // If watching a specific file, filter events for that file only
          if (filterPath != null) {
            final eventPathNormalized = event.path.replaceAll('\\', '/');
            if (eventPathNormalized != filterPath) {
              return; // Ignore events for other files
            }
          }

          final changeEvent = _convertWatchEvent(event);
          if (!controller.isClosed) {
            controller.add(changeEvent);
          }
        },
        onError: (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(
              FileWatchException(
                'Error watching path: ${error.toString()}',
                normalizedPath,
                error: error,
                stackTrace: stackTrace,
              ),
            );
          }
        },
        cancelOnError: false,
      );

      // Store watcher data
      _watchers[normalizedPath] = _WatcherData(
        watcher: watcher,
        controller: controller,
        subscription: subscription,
      );

      // Yield events from the controller
      yield* controller.stream;
    } catch (e, stackTrace) {
      // Clean up on error
      await controller.close();
      throw FileWatchException(
        'Failed to start watching path: ${e.toString()}',
        normalizedPath,
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Stop watching a path
  ///
  /// [path]: Path to stop watching
  ///
  /// Cleans up resources associated with the file watcher including:
  /// - Cancelling the stream subscription
  /// - Closing the stream controller
  /// - Removing from active watchers map
  ///
  /// This is automatically called when the stream is cancelled by all listeners.
  Future<void> stopWatching({
    required String path,
  }) async {
    // Normalize the path
    final normalizedPath = path.replaceAll('\\', '/');

    // Get watcher data
    final watcherData = _watchers[normalizedPath];
    if (watcherData == null) {
      // Not watching this path
      return;
    }

    // Cancel the subscription
    await watcherData.subscription.cancel();

    // Close the controller
    if (!watcherData.controller.isClosed) {
      await watcherData.controller.close();
    }

    // Remove from map
    _watchers.remove(normalizedPath);
  }

  /// Dispose all watchers and cleanup tracked temp files
  ///
  /// Call this when shutting down the application to clean up resources
  Future<void> disposeAll() async {
    // Stop all watchers
    final paths = _watchers.keys.toList();
    for (final path in paths) {
      await stopWatching(path: path);
    }

    // Delete all tracked temp files
    for (final filePath in _trackedTempFiles) {
      try {
        final file = File(filePath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Ignore errors during cleanup
      }
    }
    _trackedTempFiles.clear();
  }

  // ============================================================================
  // TEMPORARY FILE MANAGEMENT
  // ============================================================================

  /// Cleanup old temporary files
  ///
  /// [olderThan]: Delete files older than this duration
  /// [tempDirectory]: Optional temp directory path (uses system temp if null)
  ///
  /// Returns number of files deleted
  ///
  /// Deletes temporary files matching patterns:
  /// - tmp_*
  /// - *.tmp
  /// - *.temp
  /// - twmt_temp_*
  ///
  /// Files currently in use or locked are skipped gracefully.
  Future<Result<int, FileServiceException>> cleanupTempFiles({
    Duration olderThan = const Duration(days: 7),
    String? tempDirectory,
  }) async {
    int deletedCount = 0;
    final cutoffTime = DateTime.now().subtract(olderThan);

    try {
      final tempDir = tempDirectory != null
          ? Directory(tempDirectory)
          : Directory.systemTemp;

      if (!await tempDir.exists()) {
        return Ok(0);
      }

      // List all files recursively
      final files = await tempDir
          .list(recursive: true)
          .where((entity) => entity is File)
          .cast<File>()
          .toList();

      for (final file in files) {
        try {
          final stat = await file.stat();

          // Check if file is old enough
          if (stat.modified.isBefore(cutoffTime)) {
            // Only delete files matching temp patterns
            final fileName = path.basename(file.path);
            if (_isTempFile(fileName)) {
              await file.delete();
              deletedCount++;
            }
          }
        } on FileSystemException {
          // Skip files that are locked or inaccessible
          continue;
        }
      }

      return Ok(deletedCount);
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Failed to cleanup temp files: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Create temporary file with automatic cleanup tracking
  ///
  /// [prefix]: Optional prefix for temp file name
  /// [suffix]: Optional suffix for temp file name
  /// [autoDelete]: Whether to automatically delete on app shutdown
  ///
  /// Returns path to created temp file
  Future<Result<String, FileServiceException>> createTempFile({
    String? prefix,
    String? suffix,
    bool autoDelete = false,
  }) async {
    try {
      final tempDir = Directory.systemTemp.path;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${prefix ?? 'tmp'}_$timestamp${suffix ?? '.tmp'}';
      final filePath = path.join(tempDir, fileName);

      final file = File(filePath);
      await file.create();

      // Track file for auto-deletion if requested
      if (autoDelete) {
        _trackedTempFiles.add(filePath);
      }

      return Ok(filePath);
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Failed to create temp file: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ============================================================================
  // PATH MANAGEMENT
  // ============================================================================

  /// Get application data directory
  ///
  /// Returns path to AppData\Roaming\TWMT on Windows
  /// In debug mode: AppData\Roaming\com.github.slavyk82\twmt
  Future<String> getAppDataDirectory() async {
    return await DatabaseConfig.getAppSupportDirectory();
  }

  /// Get application config directory
  ///
  /// Returns path to AppData\Roaming\TWMT\config
  Future<String> getConfigDirectory() async {
    final appData = await getAppDataDirectory();
    final configDir = Directory(path.join(appData, 'config'));
    if (!await configDir.exists()) {
      await configDir.create(recursive: true);
    }
    return configDir.path;
  }

  /// Get application database directory
  ///
  /// Returns path to AppData\Roaming\TWMT (database location)
  Future<String> getDatabaseDirectory() async {
    return await getAppDataDirectory();
  }

  /// Get application logs directory
  ///
  /// Returns path to AppData\Local\TWMT\logs
  Future<String> getLogsDirectory() async {
    final dir = await getApplicationCacheDirectory();
    final logsDir = Directory(path.join(dir.path, 'logs'));
    if (!await logsDir.exists()) {
      await logsDir.create(recursive: true);
    }
    return logsDir.path;
  }

  /// Get application cache directory
  ///
  /// Returns path to AppData\Local\TWMT\cache
  Future<String> getCacheDirectory() async {
    final dir = await getApplicationCacheDirectory();
    final cacheDir = Directory(path.join(dir.path, 'cache'));
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  /// Get temporary directory
  ///
  /// Returns path to system temp directory
  Future<String> getTempDirectory() async {
    final dir = await Directory.systemTemp.create();
    return dir.path;
  }

  // ============================================================================
  // FILE UTILITIES
  // ============================================================================

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
  }) async {
    try {
      final file1 = File(filePath1);
      final file2 = File(filePath2);

      if (!await file1.exists()) {
        return Err(
          FileNotFoundException(
            'First file not found: $filePath1',
            filePath1,
          ),
        );
      }

      if (!await file2.exists()) {
        return Err(
          FileNotFoundException(
            'Second file not found: $filePath2',
            filePath2,
          ),
        );
      }

      if (!compareContent) {
        // Compare only size and modification time
        final stat1 = await file1.stat();
        final stat2 = await file2.stat();

        return Ok(stat1.size == stat2.size &&
            stat1.modified == stat2.modified);
      }

      // Compare content byte-by-byte
      final bytes1 = await file1.readAsBytes();
      final bytes2 = await file2.readAsBytes();

      if (bytes1.length != bytes2.length) {
        return Ok(false);
      }

      for (var i = 0; i < bytes1.length; i++) {
        if (bytes1[i] != bytes2[i]) {
          return Ok(false);
        }
      }

      return Ok(true);
    } catch (e, stackTrace) {
      return Err(
        FileServiceException(
          'Failed to compare files: ${e.toString()}',
          error: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ============================================================================
  // PRIVATE HELPER METHODS
  // ============================================================================

  /// Convert watcher package event to FileChangeEvent
  FileChangeEvent _convertWatchEvent(WatchEvent event) {
    final FileChangeType changeType;

    switch (event.type) {
      case ChangeType.ADD:
        changeType = FileChangeType.created;
        break;
      case ChangeType.MODIFY:
        changeType = FileChangeType.modified;
        break;
      case ChangeType.REMOVE:
        changeType = FileChangeType.deleted;
        break;
      default:
        // Fallback for any unexpected event types
        changeType = FileChangeType.modified;
        break;
    }

    return FileChangeEvent(
      type: changeType,
      path: event.path,
      timestamp: DateTime.now(),
    );
  }

  /// Check if a filename matches temporary file patterns
  ///
  /// Matches:
  /// - tmp_*
  /// - *.tmp
  /// - *.temp
  /// - twmt_temp_*
  bool _isTempFile(String fileName) {
    final lowerName = fileName.toLowerCase();
    return lowerName.startsWith('tmp_') ||
        lowerName.startsWith('twmt_temp_') ||
        lowerName.endsWith('.tmp') ||
        lowerName.endsWith('.temp');
  }
}

/// Internal data structure for tracking active watchers
class _WatcherData {
  /// The watcher instance (FileWatcher or DirectoryWatcher)
  final Watcher watcher;

  /// Stream controller for emitting events
  final StreamController<FileChangeEvent> controller;

  /// Subscription to the watcher's event stream
  final StreamSubscription<WatchEvent> subscription;

  _WatcherData({
    required this.watcher,
    required this.controller,
    required this.subscription,
  });
}
