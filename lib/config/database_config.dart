import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Database configuration constants and utilities for TWMT application.
///
/// Manages database paths, versions, and configuration settings according to
/// Windows desktop best practices (AppData\Roaming).
class DatabaseConfig {
  DatabaseConfig._();

  /// Database file name
  static const String databaseName = 'twmt.db';

  /// Current database schema version
  static const int databaseVersion = 7;

  /// Application directory name in AppData
  static const String appDirectoryName = 'TWMT';

  /// Get the full path to the database file in AppData\Roaming\TWMT\
  ///
  /// On Windows, this resolves to: %APPDATA%\TWMT\twmt.db
  ///
  /// Example: C:\Users\Username\AppData\Roaming\TWMT\twmt.db
  static Future<String> getDatabasePath() async {
    final directory = await getApplicationSupportDirectory();
    return path.join(directory.path, databaseName);
  }

  /// Get the application support directory path
  ///
  /// On Windows: %APPDATA%\TWMT
  static Future<String> getAppSupportDirectory() async {
    final directory = await getApplicationSupportDirectory();
    return directory.path;
  }

  /// Get the config directory path
  ///
  /// On Windows: %APPDATA%\TWMT\config
  static Future<String> getConfigDirectory() async {
    final directory = await getApplicationSupportDirectory();
    final configDir = path.join(directory.path, 'config');
    await Directory(configDir).create(recursive: true);
    return configDir;
  }

  /// Get the logs directory path
  ///
  /// On Windows: %LOCALAPPDATA%\TWMT\logs
  static Future<String> getLogsDirectory() async {
    // Use getTemporaryDirectory() which resolves to %LOCALAPPDATA%\Temp on Windows
    // Then navigate to parent to get %LOCALAPPDATA%
    final tempDir = await getTemporaryDirectory();
    final localAppData = tempDir.parent;

    final logsDir = path.join(
      localAppData.path,
      appDirectoryName,
      'logs',
    );
    await Directory(logsDir).create(recursive: true);
    return logsDir;
  }

  /// Get the cache directory path
  ///
  /// On Windows: %LOCALAPPDATA%\TWMT\cache
  static Future<String> getCacheDirectory() async {
    // Use getTemporaryDirectory() which resolves to %LOCALAPPDATA%\Temp on Windows
    // Then navigate to parent to get %LOCALAPPDATA%
    final tempDir = await getTemporaryDirectory();
    final localAppData = tempDir.parent;

    final cacheDir = path.join(
      localAppData.path,
      appDirectoryName,
      'cache',
    );
    await Directory(cacheDir).create(recursive: true);
    return cacheDir;
  }

  /// Ensure all application directories exist
  static Future<void> ensureDirectoriesExist() async {
    final appSupportDir = await getApplicationSupportDirectory();
    await Directory(appSupportDir.path).create(recursive: true);
    await getConfigDirectory();
    await getLogsDirectory();
    await getCacheDirectory();
  }

  /// Database connection configuration
  static const Map<String, dynamic> connectionConfig = {
    'journal_mode': 'WAL', // Write-Ahead Logging for better performance
    'foreign_keys': true, // Enable foreign key constraints
    'synchronous': 'NORMAL', // Balance between safety and performance
    'temp_store': 'MEMORY', // Use memory for temporary storage
    'cache_size': -2000, // 2MB cache (negative = KB)
  };

  /// Get database connection configuration as PRAGMA statements
  static List<String> getPragmaStatements() {
    return [
      'PRAGMA foreign_keys = ON',
      'PRAGMA journal_mode = WAL',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA temp_store = MEMORY',
      'PRAGMA cache_size = -2000',
    ];
  }
}
