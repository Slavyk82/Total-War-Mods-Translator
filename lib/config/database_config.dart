import 'dart:io';
import 'package:flutter/foundation.dart';
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

  /// Database schema version — FROZEN at 1. DO NOT BUMP.
  ///
  /// This value is intentionally frozen forever. All schema evolution must go
  /// through the idempotent [MigrationRegistry]
  /// (lib/services/database/migrations/migration_registry.dart), which runs at
  /// every application startup via
  /// `MigrationService.ensurePerformanceIndexes()`.
  ///
  /// Bumping this value would BRICK every existing installation:
  /// `MigrationService.runMigrations` has no incremental upgrade path — it
  /// only handles `user_version == 0` (fresh database, runs schema.sql) or
  /// `user_version == databaseVersion` (up to date). Any other value makes it
  /// throw and instruct the user to DELETE their database, losing all
  /// projects, translations, and translation memory.
  ///
  /// A tripwire test enforces this freeze:
  /// test/services/database/migration_service_version_freeze_test.dart
  static const int databaseVersion = 1;

  /// Application directory name in AppData
  static const String appDirectoryName = 'com.github.slavyk82\\twmt';

  /// Application directory name for the installed version (used in debug mode)
  /// This allows development to use the same data as the installed app
  static const String _installedAppDirectoryName = 'com.github.slavyk82\\twmt';

  /// Get the application data directory path
  ///
  /// In debug mode (a real `flutter run` dev session), uses the installed
  /// app's directory so development shares the production data. In release
  /// mode, uses the standard path_provider directory.
  ///
  /// SAFETY: the debug data-sharing override is DISABLED under `flutter test`,
  /// and a guard below hard-refuses the real installed-app directory while
  /// testing. `flutter test` runs in [kDebugMode], so without this guard every
  /// test would resolve the developer's REAL production database — and any test
  /// reaching a destructive path ([DatabaseService.deleteDatabase],
  /// [MigrationService.reset], a restore) would wipe it. Tests MUST use
  /// `TestDatabase` (in-memory) or mock path_provider with a temp directory.
  static Future<String> _getAppDataDirectory() async {
    final underTest = Platform.environment['FLUTTER_TEST'] == 'true';

    if (kDebugMode && Platform.isWindows && !underTest) {
      // Real dev session on Windows: use the installed app's directory so the
      // dev build shares the production database, settings and secure storage.
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final devPath = path.join(appData, _installedAppDirectoryName);
        if (await Directory(devPath).exists()) {
          return devPath;
        }
      }
    }

    // Default: use path_provider
    final directory = await getApplicationSupportDirectory();

    // Test guard: never let a test operate on the real installed-app data
    // directory. If path_provider was not mocked (or was mocked to the real
    // location), fail loudly instead of silently touching production data.
    if (underTest) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final realDir = path.join(appData, _installedAppDirectoryName);
        if (path.equals(directory.path, realDir)) {
          throw StateError(
            'DatabaseConfig resolved the REAL installed-app data directory '
            'under flutter test ($realDir). Tests must use TestDatabase '
            '(in-memory) or mock path_provider with a temp dir. Refusing to '
            'touch the production database.',
          );
        }
      }
    }

    return directory.path;
  }

  /// Get the full path to the database file in AppData\Roaming\TWMT\
  ///
  /// On Windows, this resolves to: %APPDATA%\TWMT\twmt.db
  /// In debug mode: %APPDATA%\com.github.slavyk82\twmt\twmt.db
  ///
  /// Example: C:\Users\Username\AppData\Roaming\TWMT\twmt.db
  static Future<String> getDatabasePath() async {
    final directory = await _getAppDataDirectory();
    return path.join(directory, databaseName);
  }

  /// Get the application support directory path
  ///
  /// On Windows: %APPDATA%\TWMT
  /// In debug mode: %APPDATA%\com.github.slavyk82\twmt
  static Future<String> getAppSupportDirectory() async {
    return await _getAppDataDirectory();
  }

  /// Get the config directory path
  ///
  /// On Windows: %APPDATA%\TWMT\config
  /// In debug mode: %APPDATA%\com.github.slavyk82\twmt\config
  static Future<String> getConfigDirectory() async {
    final directory = await _getAppDataDirectory();
    final configDir = path.join(directory, 'config');
    await Directory(configDir).create(recursive: true);
    return configDir;
  }

  /// Get the logs directory path
  ///
  /// On Windows: %LOCALAPPDATA%\<app>\logs
  ///
  /// Uses getApplicationCacheDirectory() (a stable, app-specific location)
  /// instead of deriving %LOCALAPPDATA% from getTemporaryDirectory().parent,
  /// which breaks when TMP/TEMP is redirected. This matches the logs path
  /// used by LoggingService and FileWatchService.
  static Future<String> getLogsDirectory() async {
    final cacheBase = await getApplicationCacheDirectory();

    final logsDir = path.join(cacheBase.path, 'logs');
    await Directory(logsDir).create(recursive: true);
    return logsDir;
  }

  /// Get the cache directory path
  ///
  /// On Windows: %LOCALAPPDATA%\<app>\cache
  ///
  /// Uses getApplicationCacheDirectory() (a stable, app-specific location)
  /// instead of deriving %LOCALAPPDATA% from getTemporaryDirectory().parent,
  /// which breaks when TMP/TEMP is redirected. This matches the cache path
  /// used by FileWatchService.
  static Future<String> getCacheDirectory() async {
    final cacheBase = await getApplicationCacheDirectory();

    final cacheDir = path.join(cacheBase.path, 'cache');
    await Directory(cacheDir).create(recursive: true);
    return cacheDir;
  }

  /// Ensure all application directories exist
  static Future<void> ensureDirectoriesExist() async {
    final appSupportDir = await _getAppDataDirectory();
    await Directory(appSupportDir).create(recursive: true);
    await getConfigDirectory();
    await getLogsDirectory();
    await getCacheDirectory();
  }

  /// Database connection configuration
  static const Map<String, dynamic> connectionConfig = {
    'journal_mode': 'WAL',
    'foreign_keys': true,
    'synchronous': 'NORMAL',
    'temp_store': 'MEMORY',
    'cache_size': -64000, // 64 MB cache (tuned for 6M+ TM rows)
    'mmap_size': 268435456, // 256 MB memory-mapped I/O (kernel page cache)
    'busy_timeout': 30000,
  };

  /// Get database connection configuration as PRAGMA statements
  static List<String> getPragmaStatements() {
    return [
      'PRAGMA foreign_keys = ON',
      'PRAGMA journal_mode = WAL',
      'PRAGMA synchronous = NORMAL',
      'PRAGMA temp_store = MEMORY',
      'PRAGMA cache_size = -64000',
      'PRAGMA mmap_size = 268435456',
      'PRAGMA busy_timeout = 30000',
    ];
  }
}
