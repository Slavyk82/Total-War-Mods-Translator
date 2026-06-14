// path_provider_platform_interface is a transitive dependency of
// path_provider; it is imported here only to stub directories in tests.
// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:twmt/config/database_config.dart';

/// Fake path provider with separate, test-owned cache and temp directories.
///
/// Extends (not implements) PathProviderPlatform so the platform-interface
/// token verification passes.
class _FakePathProviderPlatform extends PathProviderPlatform {
  _FakePathProviderPlatform({
    required this.cachePath,
    required this.tempPath,
  });

  final String cachePath;
  final String tempPath;

  @override
  Future<String?> getApplicationCachePath() async => cachePath;

  /// Simulates a redirected TMP/TEMP (e.g. TMP=C:\Temp): the temp directory
  /// is NOT under the application cache base, so any code deriving paths
  /// from getTemporaryDirectory().parent would land somewhere arbitrary.
  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

/// Fake that only stubs the application-support path, used to drive the
/// production-DB guard in [DatabaseConfig].
class _SupportPathFake extends PathProviderPlatform {
  _SupportPathFake({required this.supportPath});

  final String supportPath;

  @override
  Future<String?> getApplicationSupportPath() async => supportPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DatabaseConfig production-DB guard under flutter test', () {
    // Regression guard for the incident where `flutter test` (which runs in
    // kDebugMode) resolved the REAL installed-app database directory and a
    // destructive call (deleteDatabase/MigrationService.reset) wiped the
    // developer's production database. getDatabasePath() must NEVER hand back
    // the real installed-app directory while testing.

    String realInstalledDir() {
      final appData = Platform.environment['APPDATA']!;
      return path.join(appData, 'com.github.slavyk82', 'twmt');
    }

    test(
      'getDatabasePath throws when path_provider resolves the real prod dir',
      () async {
        PathProviderPlatform.instance =
            _SupportPathFake(supportPath: realInstalledDir());

        await expectLater(
          DatabaseConfig.getDatabasePath(),
          throwsA(isA<StateError>()),
        );
      },
      // The guard is Windows + APPDATA specific (the app is Windows-only).
      skip: !Platform.isWindows || Platform.environment['APPDATA'] == null,
    );

    test(
      'getDatabasePath returns a temp path unchanged (no real-dir override)',
      () async {
        final tempSupport =
            await Directory.systemTemp.createTemp('twmt_support_');
        addTearDown(() async {
          if (await tempSupport.exists()) {
            await tempSupport.delete(recursive: true);
          }
        });
        PathProviderPlatform.instance =
            _SupportPathFake(supportPath: tempSupport.path);

        final dbPath = await DatabaseConfig.getDatabasePath();

        expect(dbPath, path.join(tempSupport.path, DatabaseConfig.databaseName));
      },
      skip: !Platform.isWindows,
    );
  });

  group('DatabaseConfig logs/cache directories', () {
    late Directory root;
    late String cacheBase;
    late String redirectedTemp;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('twmt_dbconfig_test_');
      cacheBase = path.join(root.path, 'AppCache');
      redirectedTemp = path.join(root.path, 'RedirectedTemp');
      await Directory(cacheBase).create(recursive: true);
      await Directory(redirectedTemp).create(recursive: true);

      PathProviderPlatform.instance = _FakePathProviderPlatform(
        cachePath: cacheBase,
        tempPath: redirectedTemp,
      );
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('getLogsDirectory uses the application cache base, not temp.parent',
        () async {
      final logsDir = await DatabaseConfig.getLogsDirectory();

      expect(logsDir, path.join(cacheBase, 'logs'));
      expect(await Directory(logsDir).exists(), isTrue);
      // Must not be derived from the (redirected) temp directory.
      expect(path.isWithin(redirectedTemp, logsDir), isFalse);
    });

    test('getCacheDirectory uses the application cache base, not temp.parent',
        () async {
      final cacheDir = await DatabaseConfig.getCacheDirectory();

      expect(cacheDir, path.join(cacheBase, 'cache'));
      expect(await Directory(cacheDir).exists(), isTrue);
      expect(path.isWithin(redirectedTemp, cacheDir), isFalse);
    });
  });
}
